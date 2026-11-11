extends SceneTree
## A quick two-finger tap unselects everything; a pinch, a slow press or a
## single tap doesn't. The cancel button clears buildings too.
## Run: godot --headless -s res://tests/test_two_finger_tap.gd

var failures := 0
var panes: Control


func _initialize() -> void:
	root.size = Vector2i(1920, 1200)
	create_timer(60.0).timeout.connect(func(): print("FAIL timed out"); quit(1))
	root.add_child(load("res://scenes/main.tscn").instantiate())
	_run()


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func touch(index: int, at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = down
	panes._input(e)


func drag(index: int, at: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = at
	panes._input(e)


func mouse_right(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.position = at
	e.pressed = down
	panes._input(e)


func _run() -> void:
	await frames(3)
	var game: Node = root.get_node("Main/Game")
	var sim: Node = root.get_node("Main/Sim")
	panes = root.get_node("Main/Panes")
	sim.set_process(false)
	var mine: Array = sim.units.filter(func(u): return u.team == 0).map(func(u): return u.id)
	var a := Vector2(900, 700)
	var b := Vector2(1060, 720)

	game._select(mine.slice(0, 3))
	touch(0, a, true)
	touch(1, b, true)
	touch(0, a, false)
	touch(1, b, false)
	check("a quick two-finger tap unselects your hands", game.selection.is_empty())

	game._select(mine.slice(0, 3))
	touch(0, a, true)
	touch(1, b, true)
	drag(1, b + Vector2(80, 40))
	touch(0, a, false)
	touch(1, b + Vector2(80, 40), false)
	check("a pinch doesn't", game.selection.size() == 3)

	touch(0, a, true)
	touch(1, b, true)
	await create_timer(0.5).timeout
	touch(0, a, false)
	touch(1, b, false)
	check("holding two fingers down a while doesn't", game.selection.size() == 3)

	game._select_buildings([sim.hq_of(0).id])
	touch(0, a, true)
	touch(1, b, true)
	touch(1, b, false)
	touch(0, a, false)
	check("...and it unselects buildings too", game.selected_buildings.is_empty())


	# PC: a right click unselects; a right drag pans and keeps the selection.
	game._select(mine.slice(0, 3))
	var cam: Camera3D = panes._leaves()[0].camera
	var before: Vector3 = cam.target
	mouse_right(a, true)
	var move := InputEventMouseMotion.new()
	move.position = a + Vector2(120, 0)
	move.relative = Vector2(120, 0)
	move.button_mask = MOUSE_BUTTON_MASK_RIGHT
	panes._input(move)
	mouse_right(a + Vector2(120, 0), false)
	check("PC: a right drag pans and keeps the selection", game.selection.size() == 3 and cam.target != before)
	mouse_right(a, true)
	mouse_right(a, false)
	check("PC: a right click unselects", game.selection.is_empty())

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
