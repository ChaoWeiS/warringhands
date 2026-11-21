extends SceneTree
## Laying a building where your own hands stand works: they step out of the
## way (and walkers find a new way round). Enemy hands still block it.
## Run: godot --headless -s res://tests/test_build_room.gd

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


func _run() -> void:
	for i in 3:
		await process_frame
	var sim: Node = root.get_node("Main/Sim")
	sim.set_process(false)
	sim._ais.clear()
	sim.clear_units()
	sim.resources[0] = [999, 999, 999]
	var hq: Dictionary = sim.hq_of(0)
	var grid = sim.nav()
	var home := Vector2(hq.x, hq.z) / 100.0
	var spot := Vector2.INF
	for k in 16:
		var p: Vector2 = home + Vector2.from_angle(k * TAU / 16) * 30.0
		if sim.can_place("quarry", p, 0):
			spot = p
			break
	var mine: Array = []
	for i in 3:
		mine.append(sim.add_unit(0, 0, spot + Vector2(i * 2.0 - 2.0, 1.0)))
	var walker: int = sim.add_unit(0, 1, spot + Vector2(0, -3))
	sim.command_move([walker], Vector3(spot.x, 0, spot.y + 40.0))
	sim.step_ticks(3)
	check("your own hands standing there don't make the spot invalid", sim.can_place("quarry", spot, 0))
	sim.command_build(0, "quarry", spot)
	sim.step_ticks(3)
	var built: bool = sim.buildings.any(func(b): return b.btype == "quarry" and b.team == 0)
	check("the Quarry goes down", built)
	var clear: float = (sim.BUILDINGS.quarry.radius + sim.RADIUS) / 100.0
	var all_out := true
	for id in mine + [walker]:
		var u: Dictionary = sim.get_unit(id)
		all_out = all_out and (Vector2(u.x, u.z) / 100.0).distance_to(spot) >= clear - 0.01
	check("...and the hands there stepped out of its way", all_out)
	for t in 400:
		sim.step_ticks(1)
		if not sim.get_unit(walker).moving:
			break
	var w: Dictionary = sim.get_unit(walker)
	check("a hand that was walking through still gets where it was going (%.1f away)" % (Vector2(w.x, w.z) / 100.0).distance_to(spot + Vector2(0, 40)),
			(Vector2(w.x, w.z) / 100.0).distance_to(spot + Vector2(0, 40)) < 4.0)
	# An enemy standing on a spot still blocks it.
	var spot2 := Vector2.INF
	for k in 16:
		var p: Vector2 = home + Vector2.from_angle(k * TAU / 16 + 0.2) * 34.0
		if sim.can_place("mill", p, 0) and p.distance_to(spot) > 25.0:
			spot2 = p
			break
	sim.add_unit(1, 2, spot2)
	check("an enemy standing there still blocks it", not sim.can_place("mill", spot2, 0))
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
