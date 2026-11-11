extends SceneTree
## A hand sent onto a hill walks up a hillside (not through the cliff) and is
## drawn up there; on to the higher tier by its own ramp; and back down.
## Run: godot --headless -s res://tests/test_plateau.gd

var failures := 0
var sim: Node
var field: Node3D


func _initialize() -> void:
	root.size = Vector2i(1920, 1200)
	create_timer(90.0).timeout.connect(func(): print("FAIL timed out"); quit(1))
	root.add_child(load("res://scenes/main.tscn").instantiate())
	_run()


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


## An open spot on plateau i's top (not under a tree or a higher tier).
func spot_on(i: int) -> Vector2:
	var c: Vector2 = field._poly_center(field.plateaus[i])
	var want: float = field.plateau_info[i].height
	for ring in range(0, 40, 2):
		for k in 16:
			var q: Vector2 = c + Vector2.from_angle(k * TAU / 16) * ring
			if field.is_walkable(q) and is_equal_approx(field.height_at(q), want) and not field.is_slope_or_edge(q):
				return q
	return Vector2.INF


## Walks the unit to `to`; whether it used a ramp, and whether it ever went
## straight up or down a cliff.
func walk(id: int, to: Vector2) -> Dictionary:
	sim.command_move([id], Vector3(to.x, 0, to.y))
	var on_ramp := false
	var through_cliff := false
	var u0: Dictionary = sim.get_unit(id)
	var last_h: float = field.height_at(Vector2(u0.x, u0.z) / 100.0)
	for t in 900:
		sim.step_ticks(1)
		var u: Dictionary = sim.get_unit(id)
		var p := Vector2(u.x, u.z) / 100.0
		on_ramp = on_ramp or field.on_slope(p)
		# Up or down a cliff = the ground height jumps between steps.
		var h: float = field.height_at(p)
		if absf(h - last_h) > 1.0:
			if not through_cliff:
				print("  jumped from height %.1f to %.1f at %s" % [last_h, h, p])
			through_cliff = true
		last_h = h
		if not u.moving and t > 5:
			break
	var u: Dictionary = sim.get_unit(id)
	return {"at": Vector2(u.x, u.z) / 100.0, "ramp": on_ramp, "cliff": through_cliff}


func _run() -> void:
	await frames(3)
	sim = root.get_node("Main/Sim")
	field = root.get_node("Main/World/Field")
	var view: Node3D = root.get_node("Main/World/Units")
	sim.set_process(false)
	sim._ais.clear()
	sim.clear_units()
	var low: int = -1
	var high: int = -1
	for i in field.climbable:
		if field.plateau_info[i].level == 1 and low < 0:
			low = i
		if field.plateau_info[i].level == 2 and high < 0:
			high = i
	var hq: Dictionary = sim.hq_of(0)
	var home: Vector2 = Vector2(hq.x, hq.z) / 100.0 + Vector2(30, 0)
	var grid = sim.nav()
	home = Vector2(grid.cell_centre(grid.nearest_walkable(grid.cell_of(roundi(home.x * 100), roundi(home.y * 100))))) / 100.0
	var id: int = sim.add_unit(0, 1, home)

	var top: Vector2 = spot_on(low)
	var w: Dictionary = walk(id, top)
	check("a hand sent onto a plateau gets to the top (%.1f away)" % w.at.distance_to(top), w.at.distance_to(top) < 6.0)
	check("...up a ramp, not through the cliff", w.ramp and not w.cliff)
	await frames(2)
	check("...and is drawn up there (height %.1f)" % view._views[id].root.position.y,
			is_equal_approx(view._views[id].root.position.y, field.PLATEAU_HEIGHT))

	if high >= 0:
		var top2: Vector2 = spot_on(high)
		w = walk(id, top2)
		await frames(2)
		check("on to the higher tier by its ramp (height %.1f)" % view._views[id].root.position.y,
				w.at.distance_to(top2) < 6.0 and w.ramp and not w.cliff
				and is_equal_approx(view._views[id].root.position.y, field.PLATEAU_HEIGHT * 2))

	w = walk(id, home)
	await frames(2)
	check("sent back home, it comes down", w.at.distance_to(home) < 6.0 and view._views[id].root.position.y < 0.01)

	# Building on a flat top is fine.
	sim.resources[0] = [999, 999, 999]
	var placed := Vector2.INF
	var c: Vector2 = field._poly_center(field.plateaus[low])
	for ring in range(0, 50, 3):
		for k in 16:
			var q: Vector2 = c + Vector2.from_angle(k * TAU / 16) * ring
			if placed == Vector2.INF and field.height_at(q) == field.PLATEAU_HEIGHT and sim.can_place("quarry", q):
				placed = q
	check("there's room to build on the plateau top", placed != Vector2.INF)
	# A factory up there: its new hands step out onto the plateau, not off it.
	var bid: int = sim._add_building(0, "quarry", Vector2i(roundi(placed.x * 100), roundi(placed.y * 100)), true).id
	var before: int = sim.units.size()
	sim._spawn_from(sim.get_entity(bid), 0)
	var fresh: Dictionary = sim.units[before]
	check("a hand made up there steps out onto the plateau (height %.1f)" % field.height_at(Vector2(fresh.x, fresh.z) / 100.0),
			is_equal_approx(field.height_at(Vector2(fresh.x, fresh.z) / 100.0), field.PLATEAU_HEIGHT))
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
