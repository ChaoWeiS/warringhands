extends SceneTree
## Plants dot the grass, never on a building's spot (even one built later).
## Run: godot --headless -s res://tests/test_greenery.gd

var failures := 0


func _initialize() -> void:
	root.size = Vector2i(1920, 1200)
	create_timer(60.0).timeout.connect(func(): print("FAIL timed out"); quit(1))
	root.add_child(load("res://scenes/main.tscn").instantiate())
	_run()


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func near_building(g: Node, sim: Node) -> int:
	var n := 0
	for list in g._spots:
		for s in list:
			if not s.get("shown", true):
				continue
			for b in sim.buildings:
				if Vector2(s.pos.x, s.pos.z).distance_to(Vector2(b.x, b.z) / 100.0) < b.radius / 100.0:
					n += 1
	return n


func _run() -> void:
	for i in 3:
		await process_frame
	var sim: Node = root.get_node("Main/Sim")
	sim.set_process(false)
	var g: Node = root.get_node("Main/World/Resources/Greenery")
	check("there are plants on the grass (%d)" % g.count(), g.count() > 300)
	check("none where the HQs stand", near_building(g, sim) == 0)
	var shown: int = g.showing()
	var field: Node3D = root.get_node("Main/World/Field")
	# Build right on a patch of plants.
	var spot := Vector2.INF
	for list in g._spots:
		for s in list:
			var p := Vector2(s.pos.x, s.pos.z)
			if spot == Vector2.INF and field.height_at(p) < 0.5 and sim.can_place("quarry", p):
				spot = p
	sim._add_building(0, "quarry", Vector2i(roundi(spot.x * 100), roundi(spot.y * 100)), true)
	await process_frame
	await process_frame
	check("a new building hides the plants under it (%d -> %d showing)" % [shown, g.showing()],
			g.showing() < shown and near_building(g, sim) == 0)
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
