extends SceneTree
## Hands sent to attack an enemy that dies before they get there don't stop
## where they are: they carry on to where it was, and take on anyone there.
## Run: godot --headless -s res://tests/test_attack_on.gd

var failures := 0


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func _initialize() -> void:
	root.size = Vector2i(1920, 1200)
	create_timer(60.0).timeout.connect(func(): print("FAIL timed out"); quit(1))
	root.add_child(load("res://scenes/main.tscn").instantiate())
	_run()


func open_near(sim: Node, p: Vector2) -> Vector2:
	var grid = sim.nav()
	return Vector2(grid.cell_centre(grid.nearest_walkable(grid.cell_of(roundi(p.x * 100), roundi(p.y * 100))))) / 100.0


func _run() -> void:
	for i in 3:
		await process_frame
	var sim: Node = root.get_node("Main/Sim")
	sim.set_process(false)
	sim._ais.clear()
	sim.clear_units()
	var hq: Dictionary = sim.hq_of(0)
	var home: Vector2 = open_near(sim, Vector2(hq.x, hq.z) / 100.0 + Vector2(30, 0))
	var toward: Vector2 = (sim.field.get_center() - home).normalized()
	var far: Vector2 = open_near(sim, home + toward * 90.0)
	var mine: Array = []
	for i in 5:
		mine.append(sim.add_unit(0, 0, open_near(sim, home + Vector2(0, i * 3.0))))
	var target: int = sim.add_unit(1, 2, far)
	sim.get_unit(target).hold = true
	var behind: int = sim.add_unit(1, 2, open_near(sim, far + toward * 8.0))
	sim.get_unit(behind).hold = true
	sim.command_attack(mine, target)
	for t in 60:
		sim.step_ticks(1)
	# The target falls (to someone else) while they're on the way.
	sim.get_unit(target).hp = 0
	sim.step_ticks(2)
	var walking: bool = mine.all(func(id): return sim.get_unit(id).moving)
	check("its target gone, the hands keep walking (not stopping where they are)", walking)
	for t in 1200:
		sim.step_ticks(1)
		if sim.get_unit(behind).is_empty():
			break
	check("...to where it was, and take on the enemy there", sim.get_unit(behind).is_empty())
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
