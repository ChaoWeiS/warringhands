extends SceneTree
## Unit voices: every selected unit answers, orders get confirmed, and
## fights on screen make attack / defend / death sounds (off screen: quiet).
## Run: godot --headless -s res://tests/test_sounds.gd

const SimScript := preload("res://scripts/sim/sim.gd")

var failures := 0


func _initialize() -> void:
	root.size = Vector2i(1920, 1200)
	create_timer(120.0).timeout.connect(func(): print("FAIL timed out"); quit(1))
	root.add_child(load("res://scenes/main.tscn").instantiate())
	_run()


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func count(log: Array, from: int, category: String) -> int:
	return log.slice(from).filter(func(c): return c == category).size()


func _run() -> void:
	await frames(5)
	var game: Node = root.get_node("Main/Game")
	var sim: Node = root.get_node("Main/Sim")
	var view: Node3D = root.get_node("Main/World/Units")
	var panes: Control = root.get_node("Main/Panes")
	sim.set_process(false)
	sim._ais.clear()
	var sounds: Node = game.sounds
	var leaf = panes._leaves()[0]
	var cam = leaf.camera
	game.focus_home()
	await frames(2)

	# Every unit in a loop answers.
	var mine: Array = sim.units.filter(func(u): return u.team == 0).map(func(u): return u.id)
	var box := Rect2(cam.unproject_position(view.world_position(mine[0])), Vector2.ZERO)
	for id in mine.slice(0, 5):
		box = box.expand(cam.unproject_position(view.world_position(id)))
	var before: int = sounds.played.size()
	game._on_lassoed(cam, PackedVector2Array([box.position - Vector2(20, 20), Vector2(box.end.x + 20, box.position.y - 20),
			box.end + Vector2(20, 20), Vector2(box.position.x - 20, box.end.y + 20)]))
	check("every selected unit answers (%d units, %d answers)" % [game.selection.size(), count(sounds.played, before, "acknowledge")],
			game.selection.size() >= 2 and count(sounds.played, before, "acknowledge") == mini(game.selection.size(), sounds.MAX_CHORUS))
	var lines: Array = sounds.played_clips.slice(before)
	check("...all saying the same line", lines.size() >= 2 and lines.all(func(c): return c == lines[0]))
	before = sounds.played.size()
	game._last_tap.camera = null
	var hq: Dictionary = sim.hq_of(0)
	game._on_tapped(cam, cam.unproject_position(Vector3(hq.x / 100.0 + 30, 0, hq.z / 100.0 + 25)))
	check("an order gets a confirmation from each of them", count(sounds.played, before, "objective") == game.selection.size())
	await create_timer(0.3).timeout
	var at_once := 0
	for p in sounds._voices:
		if p.playing:
			at_once += 1
	check("...playing at the same time (%d voices)" % at_once, at_once >= 2)

	# A duel on screen: swings, cries, and a death.
	sim.clear_units()
	var centre := Vector2(cam.target.x, cam.target.z)
	var a: int = sim.add_unit(0, 0, centre + Vector2(-3.4, 0))
	var b: int = sim.add_unit(1, 2, centre + Vector2(3.4, 0))
	sim.get_unit(b).hp = 30
	await frames(2)
	before = sounds.played.size()
	for t in 70:  # in real time, like a game
		sim.step_ticks(1)
		await create_timer(SimScript.TICK_TIME).timeout
	await create_timer(0.6).timeout
	check("a fight on screen: attack sounds (%d)" % count(sounds.played, before, "attack"), count(sounds.played, before, "attack") >= 2)
	check("...cries when hit (%d)" % count(sounds.played, before, "defend"), count(sounds.played, before, "defend") >= 1)
	check("...and a death (%d, %s)" % [count(sounds.played, before, "death"), str(sounds.played.slice(before))], count(sounds.played, before, "death") == 1 and sim.get_unit(b).is_empty())

	# Far off screen: quiet.
	sim.clear_units()
	var far := Vector2(cam.target.x, cam.target.z) + Vector2(300, 300)
	var c: int = sim.add_unit(0, 0, far + Vector2(-3.4, 0))
	var d: int = sim.add_unit(1, 2, far + Vector2(3.4, 0))
	await frames(2)
	check("(that fight is off screen)", not game._on_screen(view.world_position(c)))
	before = sounds.played.size()
	for t in 60:
		sim.step_ticks(1)
		await process_frame
	await create_timer(0.5).timeout
	check("a fight off screen makes no sound", count(sounds.played, before, "attack") == 0
			and count(sounds.played, before, "defend") == 0)

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
