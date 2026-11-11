extends SceneTree
## Tutorial mode, played through with real taps, loops and buttons.
## Run: godot --headless -s res://tests/test_tutorial.gd

const ROCK := 0

var failures := 0


func _initialize() -> void:
	root.size = Vector2i(1920, 1200)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	create_timer(200.0).timeout.connect(func(): print("FAIL timed out"); quit(1))
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
	await frames(5)
	var game: Node = root.get_node("Main/Game")
	var sim: Node = root.get_node("Main/Sim")
	var panes: Control = root.get_node("Main/Panes")
	var hud: Control = root.get_node("Main/HUD/Economy")
	var view: Node3D = root.get_node("Main/World/Units")
	check("the old instructions are gone from the top left", not root.has_node("Main/HUD/Hint"))

	var tut: Control = game.start_tutorial()
	sim.set_process(false)
	await frames(2)
	check("tutorial: no computer player, and no enemies yet", sim.ai_of(1) == null
			and sim.units.all(func(u): return u.team == 0) and view._views.size() == sim.units.size())
	check("step 1 asks you to select a hand", tut.step == 0 and "select" in tut._text.text)

	var leaf = panes._leaves()[0]
	var cam = leaf.camera
	var hq: Dictionary = sim.hq_of(0)
	cam.target = Vector3(hq.x / 100.0 + 25, 0, hq.z / 100.0)
	cam.units_per_pixel = 0.1
	cam.refit()
	await frames(2)
	var mine: Array = sim.units.map(func(u): return u.id)
	var px := func(id): return cam.unproject_position(view.world_position(id))

	game._last_tap.camera = null
	game._on_tapped(cam, px.call(mine[0]))
	check("tapping a hand moves on to step 2 (loop)", tut.step == 1)
	# A loop around the whole army.
	var box := Rect2(px.call(mine[0]), Vector2.ZERO)
	for id in mine:
		box = box.expand(px.call(id))
	box = box.grow(30)
	game._on_lassoed(cam, PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]))
	check("a loop around several moves on to step 3 (move)", tut.step == 2 and game.selection.size() > 2)
	game._last_tap.camera = null
	game._on_tapped(cam, cam.unproject_position(Vector3(hq.x / 100.0 + 30, 0, hq.z / 100.0 + 30)))
	check("tapping the ground moves on to step 4 (camera)", tut.step == 3)
	cam.target += Vector3(20, 0, 0)
	await frames(2)
	check("moving the camera moves on to step 5 (double tap)", tut.step == 4)
	cam.target -= Vector3(20, 0, 0)
	cam.refit()
	sim.step_ticks(80)  # the army arrives and settles
	await frames(2)
	game._last_tap.camera = null
	game._on_tapped(cam, px.call(mine[0]))
	game._on_tapped(cam, px.call(mine[0]))
	check("a double tap moves on to step 6 (gather)", tut.step == 5)
	game._last_tap.camera = null
	game._on_tapped(cam, cam.unproject_position(Vector3(hq.x / 100.0, 8.0, hq.z / 100.0)))
	check("tapping the HQ with hands selected moves on to step 7 (build)", tut.step == 6)
	game._select([])
	hud._build_toggle.button_pressed = true
	hud._build_options.quarry.pressed.emit()
	var spot := Vector2.ZERO
	for d in [26.0, 34.0, 42.0]:
		for k in 16:
			var p: Vector2 = Vector2(hq.x, hq.z) / 100.0 + Vector2.from_angle(k * TAU / 16) * d
			if spot == Vector2.ZERO and sim.can_place("quarry", p, 0):
				spot = p
	game._on_tapped(cam, cam.unproject_position(Vector3(spot.x, 0, spot.y)))
	check("placing a quarry moves on to step 8 (train)", tut.step == 7)
	sim.step_ticks(210)  # built
	var quarry: Dictionary = sim.buildings.filter(func(b): return b.btype == "quarry").front()
	game._select_buildings([quarry.id])
	hud._process(0.0)
	hud._rows.quarry.train.pressed.emit()
	check("training moves on to step 9 (split the screen)", tut.step == 8)
	panes._split_leaf(panes._leaves()[0], true, 0.5)
	await frames(2)
	check("splitting the screen moves on to step 10 (merge)", tut.step == 9)
	var split = panes._splits()[0]
	panes._merge(split, split.a)
	await frames(2)
	check("merging moves on to step 11 (fight)", tut.step == 10)
	check("...and enemies show up, one of each kind", tut._enemies.size() == 3
			and tut._enemies.all(func(id): return sim.get_unit(id).team == 1))
	for id in tut._enemies:
		sim.get_unit(id).hp = 1
	sim.step_ticks(400)
	await frames(2)
	check("beating them moves on to the last step", tut.step == 11 and tut._skip.text == "Finish")
	var done := [false]
	tut.finished.connect(func(): done[0] = true)
	tut._skip.pressed.emit()
	check("Finish ends the tutorial", done[0])

	# Any step can be skipped.
	var tut2: Control = load("res://scripts/tutorial.gd").new()
	tut2.setup(game, sim, panes, hud)
	root.add_child(tut2)
	tut2._skip.pressed.emit()
	check("Skip moves on without doing the step", tut2.step == 1)

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
