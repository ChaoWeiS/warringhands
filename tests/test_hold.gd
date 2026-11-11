extends SceneTree
## Hold: units stop where they are and stay, fight only what's within reach
## (no chasing), and a new order lets them go. The Hold button sends it.
## Run: godot --headless -s res://tests/test_hold.gd

const SimScript := preload("res://scripts/sim/sim.gd")

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


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await frames(3)
	var game: Node = root.get_node("Main/Game")
	var sim: Node = root.get_node("Main/Sim")
	sim.set_process(false)
	sim._ais.clear()
	sim.clear_units()
	var hq: Dictionary = sim.hq_of(0)
	var home := Vector2(hq.x, hq.z) / 100.0 + Vector2(40, 0)

	# Walking, then Hold: it stops right there.
	var a: int = sim.add_unit(0, 0, home)
	sim.command_move([a], Vector3(home.x + 60, 0, home.y))
	sim.step_ticks(20)
	var u: Dictionary = sim.get_unit(a)
	check("(the hand is walking)", u.moving)
	sim.command_hold([a])
	sim.step_ticks(3)
	var stopped_at := Vector2(u.x, u.z)
	sim.step_ticks(60)
	check("Hold stops it where it is", not u.moving and Vector2(u.x, u.z).distance_to(stopped_at) < 150)

	# An enemy in sight but out of reach: a held hand doesn't chase it.
	var e: int = sim.add_unit(1, 2, Vector2(u.x, u.z) / 100.0 + Vector2(22, 0))
	sim.get_unit(e).hold = true  # the enemy stays put too
	sim.step_ticks(60)
	check("a held hand doesn't chase an enemy out of reach", Vector2(u.x, u.z).distance_to(stopped_at) < 150)
	# Within reach: it fights.
	sim.get_unit(e).x = u.x + 500
	sim.get_unit(e).z = u.z
	var hp_before: int = sim.get_unit(e).hp
	sim.step_ticks(60)
	var enemy: Dictionary = sim.get_unit(e)
	check("...but fights one that comes within reach", enemy.is_empty() or enemy.hp < hp_before)

	# A new order lets it go.
	sim.clear_units()
	var b: int = sim.add_unit(0, 0, home)
	sim.command_hold([b])
	sim.step_ticks(3)
	sim.command_move([b], Vector3(home.x + 50, 0, home.y))
	sim.step_ticks(40)
	var ub: Dictionary = sim.get_unit(b)
	check("a new order lets a held hand go", not ub.hold and Vector2(ub.x, ub.z).distance_to(home * 100.0) > 1000)

	# The button: holds the selection.
	game._select([b])
	sim._pending.clear()
	game.bar.hold_pressed.emit()
	var queued: Array = [] if sim._pending.is_empty() else sim._pending.values()[0]
	check("the Hold button orders the selection to hold", queued.size() == 1 and queued[0].type == "hold" and queued[0].ids == [b])
	check("...and it's the stop-sign picture", load("res://scripts/ui_style.gd").BUTTON_ICONS.has("hold"))

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
