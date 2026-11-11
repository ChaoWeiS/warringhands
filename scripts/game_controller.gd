extends Node
## Turns taps and lassos from any pane into selections and orders.
##
##   - Tap one of your units: select it.
##   - Draw a loop around units: select all of yours inside.
##   - Tap the ground with units selected: they move there.
##   - Tap an enemy (unit or building) with units selected: they attack it.
##   - Tap a resource spot with units selected: they gather from it.
##   - Attack button, then tap the ground: attack-move there (fight anything
##     on the way).
##   - Tap one of your buildings: select it (factories: train units).
##   - Build, pick a factory, then tap the ground: build it there.
## The selection is shared by every pane, so you can select in one pane and
## tap the destination in another.

@export var panes_path: NodePath
@export var sim_path: NodePath
@export var view_path: NodePath
@export var bar_path: NodePath
@export var buildings_path: NodePath
@export var hud_path: NodePath

## Which team this device controls.
const PLAYER_TEAM := 0
## How close (pixels) a tap must be to a unit to pick it.
const TAP_RADIUS := 44.0

var selection: Array = []  # unit ids
var selected_building := 0

var panes: Control
var sim: Node
var view: Node3D
var bar: Control
var buildings_view: Node3D
var hud: Control


func _ready() -> void:
	panes = get_node(panes_path)
	sim = get_node(sim_path)
	view = get_node(view_path)
	bar = get_node(bar_path)
	buildings_view = get_node(buildings_path)
	hud = get_node(hud_path)
	hud.setup(sim, PLAYER_TEAM)
	sim.enable_ai(1 - PLAYER_TEAM)  # the computer plays the other side
	panes.tapped.connect(_on_tapped)
	panes.lassoed.connect(_on_lassoed)
	panes.register_blocker(bar)
	for control in hud.blockers():
		panes.register_blocker(control)
	bar.filter_pressed.connect(_on_filter)
	bar.clear_pressed.connect(func(): _select([]))
	hud.train_pressed.connect(func(id): sim.command_train(PLAYER_TEAM, id))
	hud.play_again_pressed.connect(func(): get_tree().reload_current_scene())
	sim.unit_died.connect(_on_unit_died)
	sim.building_destroyed.connect(func(id):
		if id == selected_building:
			_select_building(0))
	sim.game_over.connect(func(winner): hud.show_game_over(winner))


func _on_tapped(camera: Camera3D, point: Vector2) -> void:
	var ground: Variant = camera.ground_at(point)
	# Placing a building?
	if hud.armed_build() != "":
		if ground != null:
			_place(hud.armed_build(), Vector2(ground.x, ground.z))
		return
	var id := _unit_at(camera, point, true)
	if id != -1 and not bar.is_attack_armed():
		_select([id])
		return
	var own_building := _building_at(ground, true)
	if own_building != 0 and not bar.is_attack_armed():
		_select_building(own_building)
		return
	if selection.is_empty():
		_select_building(0)
		return
	var enemy := _unit_at(camera, point, false)
	if enemy == -1:
		enemy = _building_at(ground, false)
	if enemy > 0:
		sim.command_attack(selection, enemy)
		view.show_attack_marker(enemy)
		bar.set_attack_armed(false)
		return
	if ground == null:
		return
	var node := _resource_at(ground)
	if node != 0 and not bar.is_attack_armed():
		sim.command_gather(selection, node)
		view.show_move_marker(ground)
		return
	if bar.is_attack_armed():
		sim.command_attack_move(selection, ground)
		view.show_move_marker(ground, true)
		bar.set_attack_armed(false)
	else:
		sim.command_move(selection, ground)
		view.show_move_marker(ground)


## Builds where tapped if possible; a red marker means "can't build here".
func _place(btype: String, ground: Vector2) -> void:
	var spec: Dictionary = sim.BUILDINGS[btype]
	if sim.can_place(btype, ground) and sim.can_afford(PLAYER_TEAM, spec.res, spec.cost):
		sim.command_build(PLAYER_TEAM, btype, ground)
		view.show_move_marker(Vector3(ground.x, 0, ground.y))
		hud.clear_build()
	else:
		view.show_move_marker(Vector3(ground.x, 0, ground.y), true)


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


## Fallen units leave the selection.
func _on_unit_died(id: int) -> void:
	if selection.has(id):
		var kept: Array = selection.duplicate()
		kept.erase(id)
		_select(kept)


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
	if not ids.is_empty() and selected_building != 0:
		_select_building(0)


func _select_building(id: int) -> void:
	selected_building = id
	buildings_view.set_selected_building(id)
	hud.show_building(id)
	if id != 0 and not selection.is_empty():
		_select([])


## Closest unit (yours if `own`, else an enemy) to a pane point, within
## TAP_RADIUS pixels, or -1.
func _unit_at(camera: Camera3D, point: Vector2, own: bool) -> int:
	var best := -1
	var best_dist := TAP_RADIUS
	for u in sim.units:
		if (u.team == PLAYER_TEAM) != own:
			continue
		var p: Vector2 = camera.unproject_position(view.world_position(u.id))
		var d: float = p.distance_to(point)
		if d <= best_dist:
			best = u.id
			best_dist = d
	return best


## A building (yours if `own`, else an enemy's) under a ground point, or 0.
func _building_at(ground: Variant, own: bool) -> int:
	if ground == null:
		return 0
	var g: Vector2 = Vector2(ground.x, ground.z) * float(sim.SCALE)
	for b in sim.buildings:
		if (b.team == PLAYER_TEAM) != own:
			continue
		if g.distance_to(Vector2(b.x, b.z)) <= b.radius + 150:
			return b.id
	return 0


## A resource spot under a ground point, or 0.
func _resource_at(ground: Vector3) -> int:
	var g: Vector2 = Vector2(ground.x, ground.z) * float(sim.SCALE)
	for n in sim.nodes:
		if g.distance_to(Vector2(n.x, n.z)) <= n.radius + 500:
			return n.id
	return 0
