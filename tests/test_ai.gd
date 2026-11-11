extends SceneTree
## The computer opponent: workers, factories, counter-training, defending,
## attack waves, winning against an idle player, and lockstep.
## Run: godot --headless -s res://tests/test_ai.gd

const SimScript := preload("res://scripts/sim/sim.gd")
const AIScript := preload("res://scripts/sim/ai.gd")
const ROCK := 0
const PAPER := 1
const SCISSORS := 2

var field: Node3D
var failures := 0


func _initialize() -> void:
	root.size = Vector2i(1920, 1200)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	create_timer(220.0).timeout.connect(func(): print("FAIL timed out"); quit(1))
	root.add_child(load("res://scenes/main.tscn").instantiate())
	_run()


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


## A fresh game with the usual starting armies; the AI plays `ai_teams`.
func new_game(ai_teams: Array) -> Node:
	var s: Node = SimScript.new()
	s.field = field
	root.add_child(s)
	s.set_process(false)
	for t in ai_teams:
		s.enable_ai(t)
	return s


func team_units(s: Node, team: int) -> Array:
	return s.units.filter(func(u): return u.team == team)


func _run() -> void:
	await frames(5)
	field = root.get_node("Main/World/Field")
	var main_sim: Node = root.get_node("Main/Sim")
	main_sim.set_process(false)
	check("the game turns the AI on for the enemy", main_sim.ai_of(1) != null and main_sim.ai_of(0) == null)

	# Opening: workers on all three resources, factories going up.
	var s := new_game([1])
	s.step_ticks(100)
	var workers: Array = team_units(s, 1).filter(func(u): return u.job == "gather")
	var worker_kinds: Array = workers.map(func(u): return u.kind)
	worker_kinds.sort()
	var covered := [false, false, false]
	for w in workers:
		if s.get_node_by_id(w.node).res == w.kind:
			covered[w.kind] = true
	check("AI puts a worker on each resource, each on its fastest one (%s)" % str(worker_kinds),
			covered == [true, true, true])
	check("...plus extra workers on its favourite unit's resource", workers.size() > 3)
	s.step_ticks(1200)  # one minute
	var factories: Array = s.buildings.filter(func(b): return b.team == 1 and b.btype != "hq")
	check("AI builds factories in the first minute (%d)" % factories.size(), factories.size() >= 2)
	var types := {}
	for f in factories:
		types[f.btype] = true
	check("...different ones", types.size() == factories.size())
	var near_home := true
	var hq1: Dictionary = s.hq_of(1)
	for f in factories:
		near_home = near_home and SimScript._dist2(f, hq1) < 6000 * 6000
	check("...next to its HQ", near_home)
	var start_count: int = 12
	s.step_ticks(1200)
	check("AI trains more units (%d, started with %d)" % [team_units(s, 1).size(), start_count],
			team_units(s, 1).size() > start_count)
	s.queue_free()

	# Counter-training: if we field nothing but rocks, it trains papers.
	s = new_game([1])
	for u in team_units(s, 0):
		s.units.erase(u)
		s._by_id.erase(u.id)
	var home: Dictionary = s.hq_of(0)
	for i in 6:
		s.add_unit(0, ROCK, Vector2(home.x, home.z) / 100.0 + Vector2(20, (i - 2.5) * 8))
	var before_ids := {}
	for u in team_units(s, 1):
		before_ids[u.id] = true
	s.step_ticks(2400)
	var trained: Array = team_units(s, 1).filter(func(u): return not before_ids.has(u.id))
	var kinds := [0, 0, 0]
	for u in trained:
		kinds[u.kind] += 1
	check("against all rocks, the AI trains mostly papers (rock %d, paper %d, scissors %d)" % kinds,
			kinds[PAPER] > kinds[ROCK] and kinds[PAPER] > kinds[SCISSORS])
	s.queue_free()

	# Defending: an enemy near its base gets the army's attention.
	s = new_game([1])
	hq1 = s.hq_of(1)
	s.step_ticks(40)
	# On the far side of their base: near their HQ, out of their army's sight.
	var scout_at: Vector2 = Vector2(hq1.x, hq1.z) / 100.0 + Vector2(38, 0)
	check("scout spot is open ground", field.is_walkable(scout_at))
	var scout: int = s.add_unit(0, SCISSORS, scout_at)
	s.step_ticks(60)
	var responding := 0
	for u in team_units(s, 1):
		if u.attack_move or u.target == scout:
			responding += 1
	check("AI sends its army at enemies near its base (%d responding)" % responding, responding >= 5)
	s.step_ticks(600)
	check("...and deals with them", s.get_unit(scout).is_empty())
	s.queue_free()

	# Attacking: after the first wave timer it marches on our HQ, and against
	# a player who does nothing it wins.
	s = new_game([1])
	for u in team_units(s, 0):
		s.units.erase(u)
		s._by_id.erase(u.id)
	var result := {"winner": -1, "tick": -1}
	s.game_over.connect(func(w):
		result.winner = w
		result.tick = s.tick)
	s.step_ticks(AIScript.FIRST_WAVE + 40)
	var marching: Array = team_units(s, 1).filter(func(u): return u.attack_move)
	var hq0: Dictionary = s.hq_of(0)
	var aimed := true
	for u in marching:
		var dx: int = u.dest_x - hq0.x
		var dz: int = u.dest_z - hq0.z
		aimed = aimed and dx * dx + dz * dz < 4500 * 4500  # formation spots around it
	check("the first wave sets off at our HQ after 2.5 min (%d units)" % marching.size(),
			marching.size() >= AIScript.FIRST_WAVE_SIZE and aimed)
	for t in 6000:
		s.step_ticks(1)
		if s.winner >= 0:
			break
	check("against an idle player the AI destroys the HQ and wins (%.1f min)" % (result.tick / 1200.0),
			result.winner == 1)
	s.queue_free()

	# Lockstep: AI against AI, twice, gives the identical game.
	var snapshots: Array = []
	for run in 2:
		var g := new_game([0, 1])
		g.step_ticks(4200)
		var snap: Array = [g.resources.duplicate(true), g.winner]
		for u in g.units:
			snap.append([u.id, u.x, u.z, u.hp, u.job])
		for b in g.buildings:
			snap.append([b.id, b.btype, b.hp, b.progress, b.queue.size()])
		snapshots.append(snap)
		g.queue_free()
	check("AI vs AI twice gives the identical game (lockstep, %d things tracked)" % snapshots[0].size(),
			snapshots[0] == snapshots[1])

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
