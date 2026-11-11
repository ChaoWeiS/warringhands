extends SceneTree
## Economy: bases, gathering, building, training, buildings in the way and
## under attack, winning, lockstep, and the on-screen controls.
## Run: godot --headless -s res://tests/test_economy.gd

const ResView := preload("res://scripts/resources_view.gd")
const SimScript := preload("res://scripts/sim/sim.gd")
const ROCK := 0
const PAPER := 1
const SCISSORS := 2

var field: Node3D
var failures := 0


func _initialize() -> void:
	root.size = Vector2i(1920, 1200)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
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


func new_sim() -> Node:
	var s: Node = SimScript.new()
	s.field = field
	root.add_child(s)
	s.set_process(false)
	s.clear_units()
	return s


func ground_of(e: Dictionary) -> Vector2:
	return Vector2(e.x, e.z) / 100.0


## A resource spot of this type on team 0's side (nearest its HQ).
func home_node(s: Node, res: int) -> Dictionary:
	var hq: Dictionary = s.hq_of(0)
	var best: Dictionary = {}
	for n in s.nodes:
		if n.res == res and (best.is_empty() or SimScript._dist2(n, hq) < SimScript._dist2(best, hq)):
			best = n
	return best


func _run() -> void:
	await frames(5)
	field = root.get_node("Main/World/Field")
	root.get_node("Main/Sim").set_process(false)
	root.get_node("Main/Sim")._ais.clear()  # these tests drive both sides by hand

	# Bases.
	var s := new_sim()
	var hq0: Dictionary = s.hq_of(0)
	var hq1: Dictionary = s.hq_of(1)
	check("each side has an HQ, mirrored", not hq0.is_empty() and not hq1.is_empty()
			and hq0.x + hq1.x == 82000 and hq0.z + hq1.z == 82000)
	check("everyone starts with 300 of each resource", s.resources == [[300, 300, 300], [300, 300, 300]])
	check("8 resource spots (stone, wood, metal on both sides)", s.nodes.size() == 8)

	# Gathering: a rock gathers stone twice as fast as other resources, and
	# carries it home.
	var stone: Dictionary = home_node(s, 0)
	var rock: int = s.add_unit(0, ROCK, ground_of(stone) + Vector2(0, 22))
	var paper: int = s.add_unit(0, PAPER, ground_of(stone) + Vector2(8, 22))
	s.command_gather([rock, paper], stone.id)
	var timers := {}
	for t in 300:
		s.step_ticks(1)
		for id in [rock, paper]:
			var u: Dictionary = s.get_unit(id)
			if u.phase == "gathering" and not timers.has(id):
				timers[id] = u.timer
	check("rocks gather stone fast, papers slowly (%s vs %s ticks)" % [timers.get(rock, "-"), timers.get(paper, "-")],
			timers.get(rock, 0) == SimScript.GATHER_TICKS_OWN and timers.get(paper, 0) == SimScript.GATHER_TICKS_OTHER)
	var before: int = s.resources[0][0]
	var amount_before: int = stone.amount
	s.step_ticks(1200)
	check("gathered stone reaches the HQ (+%d)" % (s.resources[0][0] - before), s.resources[0][0] >= before + 40)
	check("...and the spot runs down (%d left)" % stone.amount, stone.amount < amount_before)
	check("gatherers keep going back and forth", s.get_unit(rock).job == "gather")
	s.queue_free()

	# Building: costs resources, takes time, blocks the ground.
	s = new_sim()
	hq0 = s.hq_of(0)
	var spot := ground_of(hq0) + Vector2(25, -20)
	check("open ground next to the HQ can be built on", s.can_place("quarry", spot))
	check("can't build on top of the HQ", not s.can_place("quarry", ground_of(hq0)))
	check("can't build in a lake", not s.can_place("quarry", Vector2(410, 410)))
	s.command_build(0, "quarry", spot)
	s.step_ticks(3)
	var quarry: Dictionary = s.buildings.filter(func(b): return b.btype == "quarry").front()
	check("building costs 150 stone", s.resources[0][0] == 150)
	check("a new building starts under construction", quarry.progress < 10)
	check("you can't build on top of it", not s.can_place("mill", spot))
	var grid = s.nav()
	check("its ground is blocked for walking", not grid.is_walkable_cell(grid.cell_of(quarry.x, quarry.z)))
	s.command_train(0, quarry.id)
	s.step_ticks(3)
	check("can't train before it's finished", quarry.queue.is_empty() and s.resources[0][0] == 150)
	s.step_ticks(200)
	check("construction finishes after 10 s", quarry.progress >= SimScript.BUILDINGS.quarry.build)

	# Training.
	var count_before: int = s.units.size()
	s.command_train(0, quarry.id)
	s.command_train(0, quarry.id)
	s.step_ticks(3)
	check("training costs 60 stone each", s.resources[0][0] == 30 and quarry.queue.size() == 2)
	s.command_train(0, quarry.id)
	s.step_ticks(3)
	check("can't train without enough stone", quarry.queue.size() == 2 and s.resources[0][0] == 30)
	s.step_ticks(SimScript.TRAIN_TICKS * 2 + 10)
	var trained: Array = s.units.slice(count_before)
	check("two rocks come out of the quarry", trained.size() == 2 and trained.all(func(u): return u.kind == ROCK and u.team == 0))
	var outside := true
	for u in trained:
		outside = outside and SimScript._dist2(u, quarry) >= (quarry.radius + SimScript.RADIUS - 5) * (quarry.radius + SimScript.RADIUS - 5)
	check("...standing outside it", outside)
	s.command_build(0, "mill", spot + Vector2(0, 30))
	s.command_build(0, "mill", spot + Vector2(30, 30))
	s.command_build(0, "mill", spot + Vector2(-30, 30))
	s.step_ticks(3)
	check("only two mills fit the budget (300 wood)", s.buildings.filter(func(b): return b.btype == "mill").size() == 2
			and s.resources[0][1] == 0)

	# Units are pushed out of buildings.
	var squatter: int = s.add_unit(0, PAPER, ground_of(quarry))
	s.step_ticks(1)
	var sq: Dictionary = s.get_unit(squatter)
	check("units can't stand inside buildings", SimScript._dist2(sq, quarry) >= (quarry.radius + SimScript.RADIUS - 5) * (quarry.radius + SimScript.RADIUS - 5))
	s.queue_free()

	# Buildings can be attacked; losing your HQ loses the game.
	s = new_sim()
	hq0 = s.hq_of(0)
	var outcome := {"winner": -1}
	s.game_over.connect(func(w): outcome.winner = w)
	for i in 8:
		s.add_unit(1, ROCK, ground_of(hq0) + Vector2(-16, (i - 3.5) * 7))
	s.step_ticks(60)
	check("enemies attack a building in sight", hq0.hp < hq0.max_hp)
	s.step_ticks(1200)
	check("the HQ falls and the attackers win", s.hq_of(0).is_empty() and outcome.winner == 1 and s.winner == 1)
	var grid2 = s.nav()
	check("a fallen building frees its ground", grid2.is_walkable_cell(grid2.cell_of(hq0.x, hq0.z)))
	s.queue_free()

	# Gatherers don't wander off to fight, but do fight back.
	s = new_sim()
	stone = home_node(s, 0)
	var worker: int = s.add_unit(0, ROCK, ground_of(stone) + Vector2(0, 22))
	s.command_gather([worker], stone.id)
	# An enemy walks right past under a move order (so it won't start a fight).
	var passer: int = s.add_unit(1, SCISSORS, ground_of(stone) + Vector2(-30, 26))
	s.command_move([passer], Vector3(stone.x / 100.0 + 30, 0, stone.z / 100.0 + 26))
	s.step_ticks(80)
	check("a gatherer ignores enemies that leave it alone", s.get_unit(worker).job == "gather"
			and s.get_unit(passer).hp == 100)
	s.command_attack([passer], worker)
	s.step_ticks(200)
	check("...but fights back when attacked", s.get_unit(passer).is_empty() or s.get_unit(passer).hp < 100)
	s.queue_free()

	# Lockstep: the same economy game twice ends up identical.
	var snapshots: Array = []
	for run in 2:
		var g := new_sim()
		var h: Dictionary = g.hq_of(0)
		var st: Dictionary = home_node(g, 0)
		var w1: int = g.add_unit(0, ROCK, ground_of(st) + Vector2(0, 22))
		var w2: int = g.add_unit(0, SCISSORS, ground_of(st) + Vector2(8, 22))
		g.command_gather([w1, w2], st.id)
		g.command_build(0, "quarry", ground_of(h) + Vector2(25, -20))
		g.step_ticks(250)
		var q: Dictionary = g.buildings.filter(func(b): return b.btype == "quarry").front()
		g.command_train(0, q.id)
		g.step_ticks(600)
		var snap: Array = [g.resources.duplicate(true)]
		for u in g.units:
			snap.append([u.id, u.x, u.z, u.hp, u.carry])
		for b in g.buildings:
			snap.append([b.id, b.progress, b.queue.size(), b.train])
		snapshots.append(snap)
		g.queue_free()
	check("same orders give an identical economy (lockstep)", snapshots[0] == snapshots[1])

	# On-screen controls in the real game.
	var sim: Node = root.get_node("Main/Sim")
	var game: Node = root.get_node("Main/Game")
	var hud: Control = root.get_node("Main/HUD/Economy")
	var panes: Control = root.get_node("Main/Panes")
	var leaf = panes._leaves()[0]
	var cam = leaf.camera
	var my_hq: Dictionary = sim.hq_of(0)
	cam.target = Vector3(my_hq.x / 100.0, 0, my_hq.z / 100.0)
	cam.units_per_pixel = 0.08
	cam.refit()
	await frames(3)
	hud._process(0.0)
	check("resource counter shows your stock", hud._res_labels[0].text == str(sim.resources[0][0]))
	sim._pending.clear()
	hud._build_toggle.button_pressed = true
	check("Build shows the three factories", hud._build_options.quarry.visible and hud._build_options.forge.visible)
	hud._build_options.quarry.pressed.emit()
	check("picking one waits for a tap on the ground", hud.armed_build() == "quarry")
	game._on_tapped(cam, cam.unproject_position(Vector3(my_hq.x / 100.0, 0, my_hq.z / 100.0)))
	check("tapping on the HQ doesn't build there", sim._pending.is_empty() and hud.armed_build() == "quarry")
	var free_spot := Vector3(my_hq.x / 100.0 + 25, 0, my_hq.z / 100.0 - 20)
	game._on_tapped(cam, cam.unproject_position(free_spot))
	var queued: Array = [] if sim._pending.is_empty() else sim._pending.values()[0]
	check("tapping open ground orders the build", queued.size() == 1 and queued[0].type == "build" and queued[0].btype == "quarry")
	check("...and leaves build mode", hud.armed_build() == "")
	sim.step_ticks(3)
	var built: Dictionary = sim.buildings.filter(func(b): return b.btype == "quarry" and b.team == 0).front()
	built.progress = SimScript.BUILDINGS.quarry.build
	game._on_tapped(cam, cam.unproject_position(Vector3(built.x / 100.0, 0, built.z / 100.0)))
	hud._process(0.0)
	check("tapping your factory selects it and shows its panel", game.selected_building == built.id and hud.building_panel.visible)
	sim._pending.clear()
	hud._train_button.pressed.emit()
	queued = [] if sim._pending.is_empty() else sim._pending.values()[0]
	check("the train button queues a unit", queued.size() == 1 and queued[0].type == "train" and queued[0].building == built.id)
	sim._pending.clear()
	var mine: Array = sim.units.filter(func(u): return u.team == 0).map(func(u): return u.id)
	game._select(mine.slice(0, 2))
	check("selecting units closes the factory panel", game.selected_building == 0)
	var node: Dictionary = sim.nodes.filter(func(n): return n.res == 2).front()
	var nearest_metal: Dictionary = node
	for n in sim.nodes:
		if n.res == 2 and SimScript._dist2(n, my_hq) < SimScript._dist2(nearest_metal, my_hq):
			nearest_metal = n
	game._on_tapped(cam, cam.unproject_position(Vector3(nearest_metal.x / 100.0, 0, nearest_metal.z / 100.0)))
	queued = [] if sim._pending.is_empty() else sim._pending.values()[0]
	check("tapping a resource spot with units selected sends them to gather", queued.size() == 1 and queued[0].type == "gather")
	sim._pending.clear()
	# Tapping the top of a spot's model (crystal tip, tree crown) works too.
	var tops_ok := true
	var tops_tried := 0
	var leaf_rect := Rect2(Vector2.ZERO, leaf.rect.size)
	cam.units_per_pixel = 0.2  # zoomed out to see several spots
	cam.refit()
	for n in sim.nodes:
		var top := Vector3(n.x / 100.0, ResView.top_of(n.res) - 1.0, n.z / 100.0)
		var p: Vector2 = cam.unproject_position(top)
		if not leaf_rect.has_point(p):
			continue
		tops_tried += 1
		game._on_tapped(cam, p)
		queued = [] if sim._pending.is_empty() else sim._pending.values()[0]
		tops_ok = tops_ok and queued.size() == 1 and queued[0].type == "gather" and queued[0].node == n.id
		sim._pending.clear()
	check("tapping the top of a resource spot's model gathers from it (%d on screen)" % tops_tried,
			tops_ok and tops_tried >= 2)
	cam.units_per_pixel = 0.08
	cam.refit()
	var res_view: Node3D = root.get_node("Main/World/Resources")
	check("every resource spot is drawn with its amount", res_view._views.size() == sim.nodes.size()
			and res_view._views[nearest_metal.id].label.text == str(nearest_metal.amount))
	# Tapping a forest says where wood comes from.
	var forest: Dictionary = sim.field.forests.front()
	game._on_tapped(cam, cam.unproject_position(Vector3(forest.center.x, 0, forest.center.y)))
	check("tapping a forest explains where wood comes from", hud._toast.modulate.a > 0.5 and "wood" in hud._toast.text)
	sim._pending.clear()
	# An emptied spot disappears.
	nearest_metal.amount = 0
	sim.nodes.erase(nearest_metal)
	res_view._sync()
	check("an emptied resource spot goes away", not res_view._views.has(nearest_metal.id))
	sim._remove_building(sim.hq_of(1))
	await frames(2)
	check("destroying the enemy HQ shows Victory", hud.game_over_screen.visible and hud._over_label.text == "Victory!")

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
