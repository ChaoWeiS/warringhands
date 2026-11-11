extends SceneTree
## A hand sent onto a plateau walks up a ramp (not through the cliff) and is
## drawn up there; sent back down, it comes down again.
## Run: godot --headless -s res://tests/test_plateau.gd

var failures := 0


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


func _run() -> void:
	await frames(3)
	var sim: Node = root.get_node("Main/Sim")
	var view: Node3D = root.get_node("Main/World/Units")
	var field: Node3D = root.get_node("Main/World/Field")
	sim.set_process(false)
	sim._ais.clear()
	sim.clear_units()
	var r: Dictionary = field.ramps[0]
	var poly: PackedVector2Array = field.plateaus[r.plateau]
	var top: Vector2 = field._poly_center(poly)
	# Start off to the side of the plateau, away from its ramp.
	var start: Vector2 = top + r.dir.orthogonal() * 40.0
	var grid = sim.nav()
	var cell: Vector2i = grid.nearest_walkable(grid.cell_of(roundi(start.x * 100), roundi(start.y * 100)))
	start = Vector2(grid.cell_centre(cell)) / 100.0
	var id: int = sim.add_unit(0, 1, start)
	sim.command_move([id], Vector3(top.x, 0, top.y))
	var on_ramp := false
	var through_cliff := false
	for t in 600:
		sim.step_ticks(1)
		var u: Dictionary = sim.get_unit(id)
		var p := Vector2(u.x, u.z) / 100.0
		on_ramp = on_ramp or field.ramp_at(p) >= 0
		through_cliff = through_cliff or not field.is_walkable(p)
		if not u.moving and t > 5:
			break
	var u: Dictionary = sim.get_unit(id)
	var at := Vector2(u.x, u.z) / 100.0
	check("a hand sent onto a plateau gets to the top (%.1f from the middle)" % at.distance_to(top), at.distance_to(top) < 6.0)
	check("...up a ramp, not through the cliff", on_ramp and not through_cliff)
	await frames(2)
	check("...and is drawn up there (height %.1f)" % view._views[id].root.position.y,
			is_equal_approx(view._views[id].root.position.y, field.PLATEAU_HEIGHT))
	sim.command_move([id], Vector3(start.x, 0, start.y))
	for t in 600:
		sim.step_ticks(1)
		if not sim.get_unit(id).moving and t > 5:
			break
	await frames(2)
	check("sent back down, it comes down", view._views[id].root.position.y < 0.01)
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
