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

## Which team this device controls (online: the seat the server gave us).
## Something the player just did (for the tutorial): "select", "lasso",
## "move", "attack", "attack_move", "gather", "harvest", "build_<type>",
## "train", "select_kind", "repair", "lasso_buildings", "sell".
signal did(action: String)

var player_team := 0
const UI := preload("res://scripts/ui_style.gd")
const StartMenu := preload("res://scripts/start_menu.gd")
const Tutorial := preload("res://scripts/tutorial.gd")
const Sounds := preload("res://scripts/sounds.gd")
const Music := preload("res://scripts/music.gd")
const Settings := preload("res://scripts/settings.gd")
const Minimap := preload("res://scripts/minimap.gd")
## How close (pixels) a tap must be to a unit to pick it.
const TAP_RADIUS := 44.0
## Two taps this close in time (ms) and space (px), in the same pane, make a
## double tap.
const DOUBLE_TAP_MS := 350
const DOUBLE_TAP_PX := 40.0
## Zoom when a game starts (map units per pixel): base and army in view.
const HOME_ZOOM := 0.09
## Height (map units) of a building's middle, for lassoing it.
const BUILDING_MIDDLE := 10.0
const ResourcesView := preload("res://scripts/resources_view.gd")

var selection: Array = []  # unit ids
var selected_buildings: Array = []
var sounds: Node
var music: Node
var _building_camera: Camera3D = null  # pane camera the buildings were picked in
var _last_tap := {"camera": null, "point": Vector2.ZERO, "time": -100000}
var selected_building := 0  # the first of them (0 = none)

var panes: Control
var sim: Node
var view: Node3D
var bar: Control
var buildings_view: Node3D
var hud: Control
var minimap: Control


func _ready() -> void:
	panes = get_node(panes_path)
	sim = get_node(sim_path)
	view = get_node(view_path)
	bar = get_node(bar_path)
	buildings_view = get_node(buildings_path)
	hud = get_node(hud_path)
	hud.setup(sim, player_team)
	# A small map in the corner of every pane (Settings can turn it off).
	minimap = Minimap.new()
	minimap.setup(sim, sim.field, panes)
	hud.add_child(minimap)
	hud.move_child(minimap, 0)
	sim.enable_ai(1 - player_team)  # the computer plays the other side (vs Computer)
	panes.tapped.connect(_on_tapped)
	panes.lassoed.connect(_on_lassoed)
	panes.pointer_moved.connect(_on_pointer_moved)
	# Unit voices: answers to selections and orders, and combat sounds for
	# whatever is on screen.
	Settings.apply_saved()
	sounds = Sounds.new()
	add_child(sounds)
	music = Music.new()
	add_child(music)
	hud.preview_sfx = func(): sounds.respond("acknowledge", [0])
	sim.building_added.connect(_on_building_added)
	buildings_view.finished.connect(func(id):
		var b: Dictionary = sim.get_entity(id)
		if not b.is_empty():
			sounds.unit_event("build_done", Vector3(b.x, 0, b.z) / float(sim.SCALE)))
	sounds.on_screen = _on_screen
	view.sounds = sounds
	did.connect(_voice_for)
	panes.placed.connect(_on_placed)
	# Two-finger tap: unselect everything (like the cancel button).
	panes.two_finger_tapped.connect(func(_camera): _unselect_all())
	panes.register_blocker(bar)
	panes.register_blocker(bar.actions)
	hud.below_build = bar.actions
	hud.right_column = bar
	for control in hud.blockers():
		panes.register_blocker(control)
	bar.filter_pressed.connect(_on_filter)
	bar.clear_pressed.connect(_unselect_all)
	hud.train_pressed.connect(func(id):
		sim.command_train(player_team, id)
		did.emit("train"))
	hud.sell_pressed.connect(func(ids):
		sim.command_sell(player_team, ids)
		did.emit("sell"))
	hud.play_again_pressed.connect(func(): get_tree().reload_current_scene())
	sim.unit_died.connect(_on_unit_died)
	sim.building_destroyed.connect(func(id):
		if selected_buildings.has(id):
			var kept: Array = selected_buildings.duplicate()
			kept.erase(id)
			_select_buildings(kept))
	sim.game_over.connect(func(winner): hud.show_game_over(winner))
	# The start menu (not when a test drives the game).
	if get_tree().get_script() == null:
		_show_start_menu()


func _show_start_menu() -> void:
	sim.set_process(false)  # nothing moves until a game is picked
	var menu: Control = StartMenu.new()
	menu.preview_sfx = func(): sounds.respond("acknowledge", [0])
	hud.get_parent().add_child(menu)
	music.play("menu")
	panes.register_blocker(menu)
	menu.vs_computer.connect(func():
		menu.queue_free()
		music.play("battle")
		focus_home()
		sim.set_process(true))
	menu.tutorial.connect(func():
		menu.queue_free()
		start_tutorial())
	menu.online_ready.connect(func(session, seat):
		menu.queue_free()
		start_online(session, seat))


## Starts the camera(s) zoomed in on our HQ and army, not the whole map.
func focus_home() -> void:
	var hq: Dictionary = sim.hq_of(player_team)
	if hq.is_empty():
		return
	var spot := Vector2(hq.x, hq.z)
	var army: Array = sim.units.filter(func(u): return u.team == player_team)
	if not army.is_empty():
		var middle := Vector2.ZERO
		for u in army:
			middle += Vector2(u.x, u.z)
		spot = (spot + middle / army.size()) * 0.5  # between the HQ and the army
	spot /= float(sim.SCALE)
	for leaf in panes._leaves():
		leaf.camera.target = Vector3(spot.x, 0, spot.y)
		leaf.camera.units_per_pixel = HOME_ZOOM
		leaf.camera.refit()


## Tutorial: our army alone on the island (enemies come for the last lesson),
## with a step-by-step card at the top.
func start_tutorial() -> Control:
	sim._ais.clear()
	for u in sim.units.duplicate():
		if u.team != player_team:
			sim.units.erase(u)
			sim._by_id.erase(u.id)
			view.forget(u.id)
	var tutorial: Control = Tutorial.new()
	tutorial.setup(self, sim, panes, hud)
	hud.get_parent().add_child(tutorial)
	panes.register_blocker(tutorial.card())
	music.play("battle")
	focus_home()
	tutorial.finished.connect(func(): get_tree().reload_current_scene())
	sim.set_process(true)
	return tutorial


## Online against a friend: we play `seat`'s side, no computer player.
func start_online(session: Node, seat: int) -> void:
	add_child(session)
	player_team = seat
	sim._ais.clear()
	_select([])
	_select_buildings([])
	hud.setup(sim, seat)
	music.play("battle")
	focus_home()
	session.attach(sim)
	session.opponent_left.connect(func():
		if sim.winner < 0:
			sim.set_process(false)
			hud.show_message("Your opponent left"))
	session.desynced.connect(func():
		sim.set_process(false)
		hud.show_message("Games went out of sync"))
	sim.set_process(true)


func _process(_delta: float) -> void:
	# Range circles while placing (an HQ can go anywhere).
	buildings_view.show_build_range(player_team, hud.armed_build() != "" and hud.armed_build() != "hq")
	panes.placing = hud.armed_build() != ""
	if not panes.placing:
		buildings_view.hide_ghost()
	_place_building_panel()


## Keeps the building panel beside the selected buildings, in the pane they
## were picked in (bottom centre if they're out of view there).
func _place_building_panel() -> void:
	if selected_buildings.is_empty():
		return
	var leaf = null
	for l in panes._leaves():
		if l.camera == _building_camera:
			leaf = l
	if leaf == null:
		hud.place_building_panel(Rect2(), Rect2())
		return
	var around := Rect2()
	for id in selected_buildings:
		var r: Rect2 = buildings_view.screen_rect(leaf.camera, id)
		if r.has_area():
			around = r if not around.has_area() else around.merge(r)
	var pane := Rect2(Vector2.ZERO, leaf.rect.size)
	if not around.has_area() or not pane.intersects(around):
		hud.place_building_panel(Rect2(), Rect2())
		return
	hud.place_building_panel(Rect2(around.position + leaf.rect.position, around.size), leaf.rect)


func _on_tapped(camera: Camera3D, point: Vector2) -> void:
	var ground: Variant = camera.ground_at(point)
	# Placing a building?
	if hud.armed_build() != "":
		if ground != null:
			_place(hud.armed_build(), Vector2(ground.x, ground.z))
		return
	var double := _is_double_tap(camera, point)
	var id := _unit_at(camera, point, true)
	# With units selected, an enemy under the finger beats your own buildings
	# (an enemy hitting your HQ must be tappable), and beats your own units
	# when it's the closer of the two (a melee).
	var foe := -1
	if not selection.is_empty():
		foe = _unit_at(camera, point, false)
		if foe != -1 and id != -1 and _tap_distance(camera, point, id) < _tap_distance(camera, point, foe):
			foe = -1
	if foe != -1:
		_order_attack(foe)
		return
	if id != -1 and not bar.is_attack_armed():
		if double and selection.has(id):
			_select_same_kind_in_pane(camera, sim.get_unit(id).kind)
			did.emit("select_kind")
		else:
			_select([id])
			did.emit("select")
		return
	var own_building := _building_at(camera, point, ground, true)
	if own_building != 0 and not bar.is_attack_armed():
		var b: Dictionary = sim.get_entity(own_building)
		if double and b.hp < b.max_hp:
			# Double tap a damaged building: units nearby come to fix it.
			sim.command_repair(player_team, own_building)
			did.emit("repair")
			hud.toast("Units nearby are coming to repair the %s" % UI.BUILDING_NAMES[b.btype])
			_building_camera = camera
			_select_building(own_building)
		elif not selection.is_empty() and b.btype == "hq":
			# Units sent to the HQ go and gather what they're best at.
			sim.command_harvest(selection)
			did.emit("harvest")
			view.show_move_marker(Vector3(b.x / float(sim.SCALE), 0, b.z / float(sim.SCALE)))
			hud.toast("Off to gather: rocks stone, papers wood, scissors metal")
		else:
			_building_camera = camera
			_select_building(own_building)
		return
	if selection.is_empty():
		_select_building(0)
		return
	var enemy := _building_at(camera, point, ground, false)  # (enemy units were checked first)
	if enemy > 0:
		_order_attack(enemy)
		return
	if ground == null:
		return
	var node := _resource_at(camera, point)
	if node != 0 and not bar.is_attack_armed():
		sim.command_gather(selection, node)
		did.emit("gather")
		view.show_move_marker(ground)
		return
	if bar.is_attack_armed():
		sim.command_attack_move(selection, ground)
		did.emit("attack_move")
		view.show_move_marker(ground, true)
		bar.set_attack_armed(false)
	else:
		sim.command_move(selection, ground)
		did.emit("move")
		view.show_move_marker(ground)


func _order_attack(target: int) -> void:
	sim.command_attack(selection, target)
	did.emit("attack")
	view.show_attack_marker(target)
	bar.set_attack_armed(false)


func _tap_distance(camera: Camera3D, point: Vector2, unit_id: int) -> float:
	return camera.unproject_position(view.world_position(unit_id)).distance_to(point)


## A construction was laid down: a thud and hammer knocks (if on screen).
## The starting HQs come ready-built, so they make no sound.
func _on_building_added(id: int) -> void:
	var b: Dictionary = sim.get_entity(id)
	if b.is_empty() or b.progress >= sim.BUILDINGS[b.btype].build:
		return
	sounds.unit_event("build_place", Vector3(b.x, 0, b.z) / float(sim.SCALE))


## Selected units answer (all of them); ordered units confirm.
func _voice_for(action: String) -> void:
	match action:
		"select", "lasso", "select_kind":
			sounds.respond("acknowledge", selection)
		"move", "attack_move", "attack", "gather", "harvest":
			sounds.respond("objective", selection)


## Is a point in the world showing in any pane?
func _on_screen(at: Vector3) -> bool:
	for leaf in panes._leaves():
		var cam: Camera3D = leaf.camera
		if cam.is_position_in_frustum(at):
			var p: Vector2 = cam.unproject_position(at)
			if Rect2(Vector2.ZERO, leaf.rect.size).has_point(p):
				return true
	return false


## Placing: the preview follows the finger / mouse.
func _on_pointer_moved(camera: Camera3D, point: Vector2) -> void:
	var btype: String = hud.armed_build()
	var ground: Variant = camera.ground_at(point)
	if btype == "" or ground == null:
		return
	var at := Vector2(ground.x, ground.z)
	buildings_view.show_ghost(btype, player_team, at, _can_build_at(btype, at))


## Placing: the finger was lifted here.
func _on_placed(camera: Camera3D, point: Vector2) -> void:
	var ground: Variant = camera.ground_at(point)
	if hud.armed_build() != "" and ground != null:
		_place(hud.armed_build(), Vector2(ground.x, ground.z))


func _can_build_at(btype: String, at: Vector2) -> bool:
	var spec: Dictionary = sim.BUILDINGS[btype]
	return sim.can_place(btype, at, player_team) and sim.can_afford(player_team, spec.res, spec.cost)


## Builds where tapped if possible; a red marker means "can't build here".
func _place(btype: String, ground: Vector2) -> void:
	var spec: Dictionary = sim.BUILDINGS[btype]
	var x: int = roundi(ground.x * sim.SCALE)
	var z: int = roundi(ground.y * sim.SCALE)
	if btype != "hq" and not sim.in_build_range(player_team, x, z):
		hud.toast("Too far: build inside the circles around your buildings")
		view.show_move_marker(Vector3(ground.x, 0, ground.y), true)
		return
	if sim.can_place(btype, ground, player_team) and sim.can_afford(player_team, spec.res, spec.cost):
		sim.command_build(player_team, btype, ground)
		buildings_view.hide_ghost()
		did.emit("build_" + btype)
		view.show_move_marker(Vector3(ground.x, 0, ground.y))
		hud.clear_build()
	else:
		view.show_move_marker(Vector3(ground.x, 0, ground.y), true)


## A loop selects your units inside it; if there are none, your buildings
## inside it (their middle, or their base).
func _on_lassoed(camera: Camera3D, polygon: PackedVector2Array) -> void:
	var ids: Array = []
	for u in sim.units:
		if u.team != player_team:
			continue
		var p: Vector2 = camera.unproject_position(view.world_position(u.id))
		if Geometry2D.is_point_in_polygon(p, polygon):
			ids.append(u.id)
	if not ids.is_empty():
		_select(ids)
		did.emit("lasso")
		return
	var bids: Array = []
	for b in sim.buildings:
		if b.team != player_team:
			continue
		var base := Vector3(b.x, 0, b.z) / float(sim.SCALE)
		for height in [0.0, BUILDING_MIDDLE]:
			if Geometry2D.is_point_in_polygon(camera.unproject_position(base + Vector3(0, height, 0)), polygon):
				bids.append(b.id)
				break
	if not bids.is_empty():
		_building_camera = camera
		_select_buildings(bids)
		did.emit("lasso_buildings")


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


## The cancel button and a two-finger tap: nothing selected, hands or buildings.
func _unselect_all() -> void:
	_select([])
	_select_buildings([])


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
		if u.team == player_team and u.kind == kind \
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
		if (u.team == player_team) != own:
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
		if (b.team == player_team) != own:
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
		if (b.team == player_team) != own:
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
