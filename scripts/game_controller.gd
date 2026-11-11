extends Node
## Turns taps and lassos from any pane into selections and orders.
##
##   - Tap one of your units: select it. Double tap it: select all your
##     units of that type visible in the pane.
##   - Draw a loop around units: select all of yours inside (no units inside:
##     your buildings inside).
##   - Tap the ground with units selected: they move there.
##   - Tap an enemy (unit or building) with units selected: they attack it.
##   - Tap a resource spot with units selected: they gather from it.
##   - Attack button, then tap the ground: attack-move there (fight anything
##     on the way).
##   - Tap one of your buildings (anywhere on its picture): select it
##     (factories: train units).
##   - Tap your HQ with units selected: each gathers what it's fastest at.
##   - Double tap a damaged building of yours: units nearby repair it.
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
const UI := preload("res://scripts/ui_style.gd")
## How close (pixels) a tap must be to a unit to pick it.
const TAP_RADIUS := 44.0
## Two taps this close in time (ms) and space (px), in the same pane, make a
## double tap.
const DOUBLE_TAP_MS := 350
const DOUBLE_TAP_PX := 40.0
## Height (map units) of a building's middle, for lassoing it.
const BUILDING_MIDDLE := 10.0
const ResourcesView := preload("res://scripts/resources_view.gd")

var selection: Array = []  # unit ids
var selected_buildings: Array = []
var _last_tap := {"camera": null, "point": Vector2.ZERO, "time": -100000}
var selected_building := 0  # the first of them (0 = none)

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
		if selected_buildings.has(id):
			var kept: Array = selected_buildings.duplicate()
			kept.erase(id)
			_select_buildings(kept))
	sim.game_over.connect(func(winner): hud.show_game_over(winner))


func _process(_delta: float) -> void:
	buildings_view.show_build_range(PLAYER_TEAM, hud.armed_build() != "")


func _on_tapped(camera: Camera3D, point: Vector2) -> void:
	var ground: Variant = camera.ground_at(point)
	# Placing a building?
	if hud.armed_build() != "":
		if ground != null:
			_place(hud.armed_build(), Vector2(ground.x, ground.z))
		return
	var double := _is_double_tap(camera, point)
	var id := _unit_at(camera, point, true)
	if id != -1 and not bar.is_attack_armed():
		if double and selection.has(id):
			_select_same_kind_in_pane(camera, sim.get_unit(id).kind)
		else:
			_select([id])
		return
	var own_building := _building_at(camera, point, ground, true)
	if own_building != 0 and not bar.is_attack_armed():
		var b: Dictionary = sim.get_entity(own_building)
		if double and b.hp < b.max_hp:
			# Double tap a damaged building: units nearby come to fix it.
			sim.command_repair(PLAYER_TEAM, own_building)
			hud.toast("Units nearby are coming to repair the %s" % UI.BUILDING_NAMES[b.btype])
			_select_building(own_building)
		elif not selection.is_empty() and b.btype == "hq":
			# Units sent to the HQ go and gather what they're best at.
			sim.command_harvest(selection)
			view.show_move_marker(Vector3(b.x / float(sim.SCALE), 0, b.z / float(sim.SCALE)))
			hud.toast("Off to gather: rocks stone, papers wood, scissors metal")
		else:
			_select_building(own_building)
		return
	if selection.is_empty():
		_select_building(0)
		return
	var enemy := _unit_at(camera, point, false)
	if enemy == -1:
		enemy = _building_at(camera, point, ground, false)
	if enemy > 0:
		sim.command_attack(selection, enemy)
		view.show_attack_marker(enemy)
		bar.set_attack_armed(false)
		return
	if ground == null:
		return
	var node := _resource_at(camera, point)
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
	var x: int = roundi(ground.x * sim.SCALE)
	var z: int = roundi(ground.y * sim.SCALE)
	if not sim.in_build_range(PLAYER_TEAM, x, z):
		hud.toast("Too far: build inside the circles around your buildings")
		view.show_move_marker(Vector3(ground.x, 0, ground.y), true)
		return
	if sim.can_place(btype, ground, PLAYER_TEAM) and sim.can_afford(PLAYER_TEAM, spec.res, spec.cost):
		sim.command_build(PLAYER_TEAM, btype, ground)
		view.show_move_marker(Vector3(ground.x, 0, ground.y))
		hud.clear_build()
	else:
		view.show_move_marker(Vector3(ground.x, 0, ground.y), true)


## A loop selects your units inside it; if there are none, your buildings
## inside it (their middle, or their base).
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
		return
	var bids: Array = []
	for b in sim.buildings:
		if b.team != PLAYER_TEAM:
			continue
		var base := Vector3(b.x, 0, b.z) / float(sim.SCALE)
		for height in [0.0, BUILDING_MIDDLE]:
			if Geometry2D.is_point_in_polygon(camera.unproject_position(base + Vector3(0, height, 0)), polygon):
				bids.append(b.id)
				break
	if not bids.is_empty():
		_select_buildings(bids)


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
	if not ids.is_empty() and not selected_buildings.is_empty():
		_select_buildings([])


## Was this tap the second of a double tap (same pane, quick, close by)?
func _is_double_tap(camera: Camera3D, point: Vector2) -> bool:
	var now: int = Time.get_ticks_msec()
	var double: bool = _last_tap.camera == camera and now - _last_tap.time <= DOUBLE_TAP_MS \
			and point.distance_to(_last_tap.point) <= DOUBLE_TAP_PX
	# A double tap is used up; a third tap starts afresh.
	_last_tap = {"camera": null if double else camera, "point": point, "time": now}
	return double


## All your units of this kind that are visible in this pane.
func _select_same_kind_in_pane(camera: Camera3D, kind: int) -> void:
	var visible := Rect2(Vector2.ZERO, camera.get_viewport().get_visible_rect().size)
	var ids: Array = []
	for u in sim.units:
		if u.team == PLAYER_TEAM and u.kind == kind \
				and visible.has_point(camera.unproject_position(view.world_position(u.id))):
			ids.append(u.id)
	_select(ids)


func _select_building(id: int) -> void:
	_select_buildings([] if id == 0 else [id])


func _select_buildings(ids: Array) -> void:
	selected_buildings = ids.duplicate()
	selected_building = 0 if ids.is_empty() else ids[0]
	buildings_view.set_selected_buildings(ids)
	hud.show_buildings(ids)
	if not ids.is_empty() and not selection.is_empty():
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


## A building (yours if `own`, else an enemy's) under a pane point, or 0.
func _building_at(camera: Camera3D, point: Vector2, ground: Variant, own: bool) -> int:
	# On its picture: the one whose base is lowest on screen (in front) wins.
	var best := 0
	var best_foot := -INF
	for b in sim.buildings:
		if (b.team == PLAYER_TEAM) != own:
			continue
		var rect: Rect2 = buildings_view.screen_rect(camera, b.id)
		if rect.has_area() and rect.grow(6).has_point(point) and rect.end.y > best_foot:
			best = b.id
			best_foot = rect.end.y
	if best != 0 or ground == null:
		return best
	# Or on its footprint on the ground.
	var g: Vector2 = Vector2(ground.x, ground.z) * float(sim.SCALE)
	for b in sim.buildings:
		if (b.team == PLAYER_TEAM) != own:
			continue
		if g.distance_to(Vector2(b.x, b.z)) <= b.radius + 150:
			return b.id
	return 0


## The resource spot under a screen point, or 0: anywhere on its model
## (from the ground up to its top) or its ground patch, with a finger's
## width to spare. The nearest one wins.
func _resource_at(camera: Camera3D, point: Vector2) -> int:
	var best := 0
	var best_dist := INF
	for n in sim.nodes:
		var at := Vector3(n.x, 0, n.z) / float(sim.SCALE)
		var foot: Vector2 = camera.unproject_position(at)
		var head: Vector2 = camera.unproject_position(at + Vector3(0, ResourcesView.top_of(n), 0))
		var reach: float = (n.radius / float(sim.SCALE) + 3.0) / camera.units_per_pixel + TAP_RADIUS * 0.5
		var d: float = point.distance_to(Geometry2D.get_closest_point_to_segment(point, foot, head))
		if d <= reach and d < best_dist:
			best = n.id
			best_dist = d
	return best
