extends SceneTree
## Big battles stay quick: finding enemies only looks nearby (and picks the
## same enemy a full search would), whole-number square roots stay exact,
## crowds take fewer push passes, and two copies of a big fight stay in step.
## Run: godot --headless -s res://tests/test_crowd.gd

const Sim := preload("res://scripts/sim/sim.gd")

var failures := 0


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	create_timer(240.0).timeout.connect(func(): print("FAIL timed out"); quit(1))
	root.add_child(load("res://scenes/main.tscn").instantiate())
	_run()


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func _army(sim: Node, per_team: int, gap: float) -> void:
	sim._ais.clear()
	sim.clear_units()
	var c: Vector2 = sim.field.get_center()
	var grid = sim.nav()
	for team in 2:
		for i in per_team:
			var p: Vector2 = c + Vector2((team * 2 - 1) * gap + (i % 15) * 3.0, (i / 15) * 3.0 - 15)
			var cell = grid.nearest_walkable(grid.cell_of(roundi(p.x * 100), roundi(p.y * 100)))
			sim.add_unit(team, i % 3, Vector2(grid.cell_centre(cell)) / 100.0)
	for team in 2:
		var ids = sim.units.filter(func(u): return u.team == team).map(func(u): return u.id)
		sim.command_attack_move(ids, Vector3(c.x - (team * 2 - 1) * gap, 0, c.y))


func _run() -> void:
	for i in 3:
		await process_frame
	var sim: Node = root.get_node("Main/Sim")
	sim.set_process(false)

	var exact := true
	for n in [0, 1, 2, 3, 4, 15, 16, 17, 99, 100, 101, 409599, 409600, 409601, 2147395599, 2147395600, 4611686014132420609]:
		var r: int = Sim._isqrt(n)
		if not (r * r <= n and (r + 1) * (r + 1) > n):
			exact = false
			print("  isqrt(%d) = %d" % [n, r])
	check("whole-number square roots are exact", exact)

	check("a small army pushes apart 8 times a tick", Sim.push_passes(60) == Sim.PUSH_PASSES)
	check("a big crowd fewer times (but at least %d)" % Sim.MIN_PUSH_PASSES,
			Sim.push_passes(300) < Sim.PUSH_PASSES and Sim.push_passes(2000) == Sim.MIN_PUSH_PASSES)

	# Two armies close enough to see each other, mid-fight.
	_army(sim, 150, 12)
	sim.step_ticks(30)
	sim._sight_buckets = sim._team_buckets(sim.SIGHT)
	var nearby: Array = sim.units.map(func(u): return sim._nearest_enemy(u, sim.SIGHT).get("id", 0))
	sim._sight_buckets = {}
	var full: Array = sim.units.map(func(u): return sim._nearest_enemy(u, sim.SIGHT).get("id", 0))
	check("looking nearby finds the same enemy as searching everyone (%d hands)" % sim.units.size(), nearby == full)
	check("...and most hands have one in sight", full.filter(func(id): return id != 0).size() > sim.units.size() / 2)

	var t0 := Time.get_ticks_usec()
	sim.step_ticks(40)
	var ms: float = (Time.get_ticks_usec() - t0) / 1000.0 / 40.0
	print("  %d hands: %.1f ms a tick" % [sim.units.size(), ms])
	check("a 300-hand battle takes well under a tick's 50 ms", ms < 40.0)

	# The same fight twice from the same start ends the same.
	var start_id: int = sim._next_id
	var start_tick: int = sim.tick
	_army(sim, 120, 12)
	sim.step_ticks(80)
	var first: int = sim.state_hash()
	sim._next_id = start_id
	sim.tick = start_tick
	_army(sim, 120, 12)
	sim.step_ticks(80)
	check("the same big fight twice ends exactly the same", sim.state_hash() == first)

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
