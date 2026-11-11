extends SceneTree
## Queued orders: with the Queue button held (or Shift), orders go after
## what units are doing; they're done in turn. A plain order replaces the
## plan; Hold cancels it.
## Run: godot --headless -s res://tests/test_queue.gd

var failures := 0
var sim: Node


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


## An open spot near `p`.
func open_near(p: Vector2) -> Vector2:
	var grid = sim.nav()
	return Vector2(grid.cell_centre(grid.nearest_walkable(grid.cell_of(roundi(p.x * 100), roundi(p.y * 100))))) / 100.0


func v3(p: Vector2) -> Vector3:
	return Vector3(p.x, 0, p.y)


func _run() -> void:
	await frames(3)
	var game: Node = root.get_node("Main/Game")
	sim = root.get_node("Main/Sim")
	var view: Node3D = root.get_node("Main/World/Units")
	sim.set_process(false)
	sim._ais.clear()
	sim.clear_units()
	var hq: Dictionary = sim.hq_of(0)
	var home: Vector2 = open_near(Vector2(hq.x, hq.z) / 100.0 + Vector2(35, 0))
	var b: Vector2 = open_near(home + Vector2(30, 0))
	var c: Vector2 = open_near(home + Vector2(30, 30))
	var d: Vector2 = open_near(home + Vector2(0, 30))

	# A path: B, then C, then D.
	var id: int = sim.add_unit(0, 0, home)
	sim.command_move([id], v3(b))
	sim.command_move([id], v3(c), true)
	sim.command_move([id], v3(d), true)
	sim.step_ticks(4)
	check("queued orders wait their turn (%d queued)" % sim.get_unit(id).orders.size(), sim.get_unit(id).orders.size() == 2)
	var near_c := false
	for t in 900:
		sim.step_ticks(1)
		var u: Dictionary = sim.get_unit(id)
		near_c = near_c or Vector2(u.x, u.z).distance_to(c * 100) < 300
		if u.orders.is_empty() and not u.moving and t > 10:
			break
	var u: Dictionary = sim.get_unit(id)
	check("...and are done in order: via C, ending at D (%.1f away)" % (Vector2(u.x, u.z) / 100.0).distance_to(d),
			near_c and (Vector2(u.x, u.z) / 100.0).distance_to(d) < 3.0)

	# Move, then attack: the attack comes after arriving.
	var foe: int = sim.add_unit(1, 2, open_near(b + Vector2(0, -25)))
	sim.get_unit(foe).hold = true
	sim.get_unit(foe).hp = 20
	sim.command_move([id], v3(b))
	sim.command_attack([id], foe, true)
	sim.step_ticks(4)
	check("a queued attack waits for the move", sim.get_unit(id).target == 0 and sim.get_unit(id).orders.size() == 1)
	for t in 900:
		sim.step_ticks(1)
		if sim.get_unit(foe).is_empty():
			break
	check("...then the unit goes and attacks", sim.get_unit(foe).is_empty())

	# A plain order replaces the plan; Hold cancels it.
	sim.command_move([id], v3(c))
	sim.command_move([id], v3(d), true)
	sim.step_ticks(3)
	sim.command_move([id], v3(b))
	sim.step_ticks(3)
	check("a plain order replaces the queued plan", sim.get_unit(id).orders.is_empty())
	sim.command_move([id], v3(c), true)
	sim.step_ticks(3)
	sim.command_hold([id])
	sim.step_ticks(3)
	check("Hold cancels the queued orders", sim.get_unit(id).orders.is_empty() and not sim.get_unit(id).moving)

	# Idle with nothing queued: a queued order starts at once.
	sim.command_move([id], v3(d), true)
	sim.step_ticks(3)
	check("an idle unit starts a queued order right away", sim.get_unit(id).moving and sim.get_unit(id).orders.is_empty())

	# The view draws the route through the queued stops.
	var walker: int = sim.add_unit(0, 1, home)
	sim.command_move([walker], v3(d))
	sim.command_move([walker], v3(c), true)
	sim.step_ticks(4)
	id = walker
	game._select([id])
	check("the route shows the queued stops", view._step_point(sim.get_unit(id).orders[0]) == c)

	# The button: taps while it's held are queued.
	sim._pending.clear()
	game.bar._set_queue(true)
	var cam: Camera3D = root.get_node("Main/Panes")._leaves()[0].camera
	var spot: Vector2 = open_near(home + Vector2(15, -18))
	cam.target = v3(spot)
	cam.units_per_pixel = 0.05  # close in: a tap picks only what's under it
	cam.refit()
	await frames(2)
	game._last_tap.camera = null
	game._on_tapped(cam, cam.unproject_position(v3(spot)))
	var queued: Array = [] if sim._pending.is_empty() else sim._pending.values()[0]
	check("holding Queue makes a tap a queued order", queued.size() == 1 and queued[0].get("queued", false))
	game.bar._set_queue(false)
	sim._pending.clear()
	game._last_tap.camera = null
	game._on_tapped(cam, cam.unproject_position(v3(spot + Vector2(-4, 0))))
	queued = [] if sim._pending.is_empty() else sim._pending.values()[0]
	check("...let go, orders are plain again", queued.size() == 1 and not queued[0].get("queued", false))
	check("there's a Queue button with the actions", game.bar.queue_button.get_parent() == game.bar.actions)

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
