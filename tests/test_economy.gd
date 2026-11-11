extends SceneTree
## Economy: bases, gathering, building, training, buildings in the way and
## under attack, winning, lockstep, and the on-screen controls.
## Run: godot --headless -s res://tests/test_economy.gd

const ResView := preload("res://scripts/resources_view.gd")
const UI := preload("res://scripts/ui_style.gd")
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
	var trees: Array = s.nodes.filter(func(n): return n.tree)
	check("8 resource spots (stone, wood, metal on both sides)", s.nodes.size() - trees.size() == 8)
	check("every forest tree can be cut for wood (%d trees)" % trees.size(),
			trees.size() > 100 and trees.all(func(n): return n.res == 1 and n.amount == SimScript.TREE_AMOUNT))

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

	# Cutting trees: the tree nearest our HQ, nearly used up.
	s = new_sim()
	hq0 = s.hq_of(0)
	var tree: Dictionary = {}
	for n in s.nodes:
		if n.tree and (tree.is_empty() or SimScript._dist2(n, hq0) < SimScript._dist2(tree, hq0)):
			tree = n
	tree.amount = SimScript.CARRY  # one trip's worth
	var tgrid = s.nav()
	var toward: Vector2 = (ground_of(hq0) - ground_of(tree)).normalized()
	var stand: Vector2 = ground_of(tree) + toward * 12.0
	var stand_cell: Vector2i = tgrid.nearest_walkable(tgrid.cell_of(roundi(stand.x * 100), roundi(stand.y * 100)))
	var tree_cell: Vector2i = tgrid.cell_of(tree.x, tree.z)
	check("a standing tree blocks the ground", not tgrid.is_walkable_cell(tree_cell))
	var lumberjack: int = s.add_unit(0, PAPER, Vector2(tgrid.cell_centre(stand_cell)) / 100.0)
	s.command_gather([lumberjack], tree.id)
	for t in 1200:
		s.step_ticks(1)
		if s.get_node_by_id(tree.id).is_empty():
			break
	check("the tree gets cut down", s.get_node_by_id(tree.id).is_empty())
	check("...and its ground opens up", tgrid.is_walkable_cell(tree_cell))
	s.step_ticks(400)
	var lj: Dictionary = s.get_unit(lumberjack)
	var next_tree: Dictionary = s.get_node_by_id(lj.node)
	check("the gatherer moves on to the next tree by itself", lj.job == "gather"
			and not next_tree.is_empty() and next_tree.tree and s.resources[0][1] >= 300 + SimScript.CARRY)
	var fresh = new_sim()
	check("a cut tree doesn't open the ground in other games", not fresh.nav().is_walkable_cell(tree_cell))
	fresh.queue_free()
	s.queue_free()

	# Building: costs resources, takes time, blocks the ground.
	s = new_sim()
	hq0 = s.hq_of(0)
	var spot := ground_of(hq0) + Vector2(25, -20)
	check("open ground next to the HQ can be built on", s.can_place("quarry", spot))
	check("can't build on top of the HQ", not s.can_place("quarry", ground_of(hq0)))
	check("can't build in a lake", not s.can_place("quarry", Vector2(410, 410)))
	# Build range: open ground too far from any of our buildings.
	var far := Vector2.ZERO
	for d in range(60, 120, 4):
		for k in 16:
			var p: Vector2 = ground_of(hq0) + Vector2.from_angle(k * TAU / 16) * d
			if far == Vector2.ZERO and s.can_place("quarry", p):
				far = p
	check("only near your own buildings: open ground %d away is out of range" % roundi(far.distance_to(ground_of(hq0))),
			far != Vector2.ZERO and not s.can_place("quarry", far, 0) and s.can_place("quarry", spot, 0))
	s.command_build(0, "quarry", far)
	s.step_ticks(3)
	check("...and a build order there does nothing", s.buildings.size() == 2 and s.resources[0][0] == 300)
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
	check("a finished building extends the build range", s.in_build_range(0,
			quarry.x + (quarry.x - hq0.x) * SimScript.BUILD_RANGE / maxi(1, absi(quarry.x - hq0.x) + absi(quarry.z - hq0.z)),
			quarry.z + (quarry.z - hq0.z) * SimScript.BUILD_RANGE / maxi(1, absi(quarry.x - hq0.x) + absi(quarry.z - hq0.z))))
	# Drop-offs: stone goes to whichever is nearer, the quarry or the HQ.
	var hauler: int = s.add_unit(0, ROCK, ground_of(quarry) + (ground_of(quarry) - ground_of(hq0)).normalized() * 12.0)
	var hu: Dictionary = s.get_unit(hauler)
	hu.carry = 20
	hu.carry_res = 0
	check("stone goes to the quarry when it's nearer", s._drop_for(hu).get("id") == quarry.id)
	hu.carry_res = 1
	check("wood doesn't (a quarry only takes stone)", s._drop_for(hu).get("id") == hq0.id)
	hu.carry_res = 0
	hu.job = "gather"
	hu.phase = "to_drop"
	hu.node = home_node(s, 0).id
	var stone_before: int = s.resources[0][0]
	var hq_dist: int = SimScript._dist2(hu, hq0)
	s.step_ticks(80)
	check("the load is dropped at the quarry (+%d stone)" % (s.resources[0][0] - stone_before),
			s.resources[0][0] == stone_before + 20 and SimScript._dist2(hu, hq0) >= hq_dist * 0.5)
	s.units.erase(hu)
	s._by_id.erase(hauler)
	s.resources[0][0] = stone_before  # back to where the checks below expect

	# Auto-gather: each unit off to the resource it's fastest at.
	var trio: Array = []
	for k in 3:
		trio.append(s.add_unit(0, k, ground_of(hq0) + Vector2(14, (k - 1) * 7)))
	s.command_harvest(trio)
	s.step_ticks(4)
	var trio_ok := true
	for id in trio:
		var tu: Dictionary = s.get_unit(id)
		trio_ok = trio_ok and tu.job == "gather" and s.get_node_by_id(tu.node).res == tu.kind
	check("sent to the HQ, each unit gathers its own resource (rock stone, paper wood, scissors metal)", trio_ok)
	# Repair: units near a damaged building come and fix it; far ones don't.
	hq0.hp = 1700
	var far_one: int = s.add_unit(0, ROCK, ground_of(hq0) + Vector2(0, 0))
	var fu: Dictionary = s.get_unit(far_one)
	var nav_far = s.nav()
	var far_cell: Vector2i = nav_far.nearest_walkable(nav_far.cell_of(hq0.x + 9000, hq0.z))
	fu.x = nav_far.cell_centre(far_cell).x
	fu.z = nav_far.cell_centre(far_cell).y
	fu.px = fu.x
	fu.pz = fu.z
	var repaired_total := [0]
	s.building_repaired.connect(func(_id, amount): repaired_total[0] += amount)
	s.command_repair(0, hq0.id)
	s.step_ticks(4)
	var repairing: Array = s.units.filter(func(u): return u.team == 0 and u.job == "repair")
	check("repair call: units nearby answer (%d), far ones don't" % repairing.size(),
			repairing.size() == trio.size() and fu.job != "repair")
	for t in 1200:
		s.step_ticks(1)
		if hq0.hp >= hq0.max_hp:
			break
	check("...and repair it to full (+%d HP)" % repaired_total[0], hq0.hp == hq0.max_hp and repaired_total[0] == 300)
	s.step_ticks(2)
	check("...then stop", s.units.filter(func(u): return u.job == "repair").is_empty())
	for id in trio + [far_one]:
		s.units.erase(s.get_unit(id))
		s._by_id.erase(id)

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
	var to_work := true
	for u in trained:
		to_work = to_work and u.job == "gather" and s.get_node_by_id(u.node).res == 0
	check("...and go straight to gathering stone (no fight on)", to_work)
	# With an enemy at the gates, new units stay ready instead.
	var raider: int = s.add_unit(1, PAPER, ground_of(hq0) + Vector2(-40, 0))
	check("an enemy near your base means a fight is on", s.in_fight(0))
	s.resources[0][0] += 60
	s.command_train(0, quarry.id)
	s.step_ticks(SimScript.TRAIN_TICKS + 10)
	var fresh_unit: Dictionary = s.units.filter(func(u): return u.team == 0 and u.kind == ROCK).back()
	check("...so a new unit doesn't go off gathering", fresh_unit.job == "")
	s.units.erase(s.get_unit(raider))
	s._by_id.erase(raider)
	s.units.erase(fresh_unit)
	s._by_id.erase(fresh_unit.id)
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

	# Another HQ: 150 of every resource, anywhere on the map; you only lose
	# with your last HQ.
	s = new_sim()
	hq0 = s.hq_of(0)
	var outpost := Vector2.ZERO
	for d in range(90, 200, 6):
		for k in 16:
			var p: Vector2 = ground_of(hq0) + Vector2.from_angle(k * TAU / 16) * d
			if outpost == Vector2.ZERO and s.can_place("hq", p, 0):
				outpost = p
	check("an HQ can go far from your base (%d away)" % roundi(outpost.distance_to(ground_of(hq0))),
			outpost != Vector2.ZERO and not s.in_build_range(0, roundi(outpost.x * 100), roundi(outpost.y * 100)))
	check("...costing 150 of every resource", SimScript.cost_of("hq") == [150, 150, 150])
	s.resources[0] = [150, 150, 140]
	s.command_build(0, "hq", outpost)
	s.step_ticks(3)
	check("...so not without enough metal", s.buildings.size() == 2)
	s.resources[0] = [200, 200, 200]
	s.command_build(0, "hq", outpost)
	s.step_ticks(3)
	var hqs: Array = s.buildings.filter(func(b): return b.team == 0 and b.btype == "hq")
	check("a second HQ goes up, paid in stone, wood and metal", hqs.size() == 2 and s.resources[0] == [50, 50, 50]
			and hqs[1].progress < SimScript.BUILDINGS.hq.build)
	var lost := {"winner": -1}
	s.game_over.connect(func(w): lost.winner = w)
	s._remove_building(hq0)
	check("losing one HQ while you have another isn't defeat", s.winner == -1 and lost.winner == -1)
	s._remove_building(hqs[1])
	check("losing the last one is", s.winner == 1 and lost.winner == 1)
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
	var buildings_view: Node3D = root.get_node("Main/World/Buildings")
	var view_units: Node3D = root.get_node("Main/World/Units")
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
	check("Build shows the three factories and an HQ", hud._build_options.quarry.visible and hud._build_options.forge.visible
			and hud._build_options.hq.visible)
	var quarry_option: Button = hud._build_options.quarry
	var shown_words: Array = quarry_option.find_children("*", "Label", true, false).map(func(l): return l.text)
	var shown_icons: Array = quarry_option.find_children("*", "TextureRect", true, false).map(func(t): return t.texture)
	check("prices show resource icons, not words (%s)" % ", ".join(shown_words), not "stone" in " ".join(shown_words)
			and "150" in shown_words and shown_icons.has(UI.res_icon(0))
			and hud._build_options.hq.find_children("*", "TextureRect", true, false).size() == 4)
	hud._build_options.quarry.pressed.emit()
	check("picking one waits for a tap on the ground", hud.armed_build() == "quarry")
	game._on_tapped(cam, cam.unproject_position(Vector3(my_hq.x / 100.0, 0, my_hq.z / 100.0)))
	check("tapping on the HQ doesn't build there", sim._pending.is_empty() and hud.armed_build() == "quarry")
	game._process(0.0)
	check("while placing, the build range shows around your buildings", buildings_view._ranges.visible
			and buildings_view._ranges.get_child_count() > 0)
	var too_far := Vector3(my_hq.x / 100.0 + 70, 0, my_hq.z / 100.0)
	game._on_tapped(cam, cam.unproject_position(too_far))
	check("tapping out of range doesn't build and says why", sim._pending.is_empty() and hud.armed_build() == "quarry"
			and "far" in hud._toast.text)
	var free_spot := Vector3.ZERO  # open ground near the HQ, nobody standing there
	for d in [28.0, 34.0, 40.0]:
		for k in 16:
			var p: Vector2 = Vector2(my_hq.x, my_hq.z) / 100.0 + Vector2.from_angle(k * TAU / 16) * d
			if free_spot == Vector3.ZERO and sim.can_place("quarry", p, 0):
				free_spot = Vector3(p.x, 0, p.y)
	game._on_tapped(cam, cam.unproject_position(free_spot))
	var queued: Array = [] if sim._pending.is_empty() else sim._pending.values()[0]
	check("tapping open ground orders the build", queued.size() == 1 and queued[0].type == "build" and queued[0].btype == "quarry")
	check("...and leaves build mode", hud.armed_build() == "")
	# Placing by finger: press, drag (a see-through preview follows), lift = build.
	sim.step_ticks(3)  # (the quarry ordered above goes up first)
	sim._pending.clear()
	hud._build_toggle.button_pressed = true
	hud._build_options.mill.pressed.emit()
	game._process(0.0)
	var mill_spots: Array = []
	for d in [30.0, 36.0, 42.0]:
		for k in 16:
			var p: Vector2 = Vector2(my_hq.x, my_hq.z) / 100.0 + Vector2.from_angle(k * TAU / 16) * d
			if sim.can_place("mill", p, 0) and p.distance_to(Vector2(free_spot.x, free_spot.z)) > 22:
				mill_spots.append(p)
	var screen_of := func(p: Vector2) -> Vector2: return leaf.rect.position + cam.unproject_position(Vector3(p.x, 0, p.y))
	var touch := func(at: Vector2, down: bool):
		var e := InputEventScreenTouch.new()
		e.index = 0
		e.position = at
		e.pressed = down
		panes._input(e)
	var drag := func(at: Vector2):
		var e := InputEventScreenDrag.new()
		e.index = 0
		e.position = at
		panes._input(e)
	touch.call(screen_of.call(mill_spots[0]), true)
	check("touching the map while placing shows a see-through preview", buildings_view.ghost_visible()
			and Vector2(buildings_view._ghost.position.x, buildings_view._ghost.position.z).distance_to(mill_spots[0]) < 0.5
			and is_equal_approx(buildings_view._ghost.get_node("Art").modulate.a, 0.5))
	var last: Vector2 = mill_spots[mill_spots.size() - 1]
	for i in 6:
		drag.call(screen_of.call(mill_spots[0].lerp(last, (i + 1) / 6.0)))
	check("...that follows the finger", Vector2(buildings_view._ghost.position.x, buildings_view._ghost.position.z).distance_to(last) < 0.5)
	check("...and nothing is built until the finger lifts", sim._pending.is_empty())
	touch.call(screen_of.call(last), false)
	queued = [] if sim._pending.is_empty() else sim._pending.values()[0]
	check("lifting the finger builds it there", queued.size() == 1 and queued[0].btype == "mill"
			and Vector2(queued[0].x, queued[0].z).distance_to(last * 100) < 60 and not buildings_view.ghost_visible())
	sim._pending.clear()
	# Lifting over a button builds nothing.
	hud._build_toggle.button_pressed = true
	hud._build_options.forge.pressed.emit()
	game._process(0.0)
	touch.call(screen_of.call(mill_spots[0]), true)
	var on_button: Vector2 = hud._build_toggle.get_global_rect().get_center()
	drag.call(on_button)
	touch.call(on_button, false)
	check("lifting over a button builds nothing", sim._pending.is_empty() and hud.armed_build() == "forge")
	hud._build_toggle.button_pressed = false
	game._process(0.0)
	check("cancelling hides the preview", not buildings_view.ghost_visible() and not panes.placing)
	sim.step_ticks(3)
	var built: Dictionary = sim.buildings.filter(func(b): return b.btype == "quarry" and b.team == 0).front()
	built.progress = SimScript.BUILDINGS.quarry.build
	game._on_tapped(cam, cam.unproject_position(Vector3(built.x / 100.0, 0, built.z / 100.0)))
	hud._process(0.0)
	check("tapping your factory selects it and shows its panel", game.selected_building == built.id and hud.building_panel.visible)
	game._process(0.0)
	var pic_rect: Rect2 = buildings_view.screen_rect(cam, built.id)
	pic_rect.position += leaf.rect.position
	var panel_rect: Rect2 = hud.building_panel.get_global_rect()
	var beside: bool = absf(panel_rect.position.x - (pic_rect.end.x + 14)) < 2 or absf(panel_rect.end.x - (pic_rect.position.x - 14)) < 2
	check("its panel sits right beside it", beside and panel_rect.position.y < pic_rect.end.y
			and panel_rect.end.y > pic_rect.position.y)
	sim._pending.clear()
	hud._train_button.pressed.emit()
	queued = [] if sim._pending.is_empty() else sim._pending.values()[0]
	check("the train button queues a unit", queued.size() == 1 and queued[0].type == "train" and queued[0].building == built.id)
	sim._pending.clear()
	var mine: Array = sim.units.filter(func(u): return u.team == 0).map(func(u): return u.id)
	game._select(mine.slice(0, 2))
	check("selecting units closes the factory panel", game.selected_building == 0)
	# Tapping high up on a building's picture (not its ground circle) selects it.
	var pic: Rect2 = buildings_view.screen_rect(cam, built.id)
	var high_up: Vector2 = pic.position + Vector2(pic.size.x * 0.5, pic.size.y * 0.15)
	var footprint_px: float = cam.unproject_position(Vector3(built.x / 100.0, 0, built.z / 100.0)).distance_to(high_up)
	game._on_tapped(cam, high_up)
	check("tapping the top of a building's picture selects it (%d px above its base)" % footprint_px,
			game.selected_buildings == [built.id] and footprint_px > 60)
	game._select([])
	game._select_buildings([])
	# Lasso around the HQ and the quarry (a thin band from one to the other,
	# clear of the army): both get selected, one panel row each.
	var a_pt: Vector2 = cam.unproject_position(Vector3(my_hq.x / 100.0, 10.0, my_hq.z / 100.0))
	var b_pt: Vector2 = cam.unproject_position(Vector3(built.x / 100.0, 10.0, built.z / 100.0))
	var across: Vector2 = (b_pt - a_pt).orthogonal().normalized() * 12.0
	var along: Vector2 = (b_pt - a_pt).normalized() * 20.0
	var band := PackedVector2Array([a_pt - along - across, b_pt + along - across, b_pt + along + across, a_pt - along + across])
	var unit_inside := false
	for id in mine:
		unit_inside = unit_inside or Geometry2D.is_point_in_polygon(cam.unproject_position(view_units.world_position(id)), band)
	game._on_lassoed(cam, band)
	hud._process(0.0)
	check("lassoing your buildings selects them", not unit_inside and game.selected_buildings.size() == 2
			and game.selected_buildings.has(my_hq.id) and game.selected_buildings.has(built.id))
	check("...with a panel row for each type", hud._rows.size() == 2 and hud._rows.has("hq") and hud._rows.has("quarry")
			and buildings_view._views[my_hq.id].ring.visible and buildings_view._views[built.id].ring.visible)
	sim._pending.clear()
	hud._rows.quarry.train.pressed.emit()
	queued = [] if sim._pending.is_empty() else sim._pending.values()[0]
	check("...and the quarry row trains at the quarry", queued.size() == 1 and queued[0].type == "train"
			and queued[0].building == built.id)
	sim._pending.clear()
	game._select(mine.slice(0, 2))
	check("lassoing units after that drops the buildings", game.selected_buildings.is_empty())
	# Double tap a unit: all your units of that type in the pane.
	game._last_tap.camera = null
	var rock0: Dictionary = sim.units.filter(func(u): return u.team == 0 and u.kind == ROCK).front()
	var rock_px: Vector2 = cam.unproject_position(view_units.world_position(rock0.id))
	game._on_tapped(cam, rock_px)
	var after_one: Array = game.selection.duplicate()
	game._on_tapped(cam, rock_px)
	var rocks_in_view := 0
	for u in sim.units:
		if u.team == 0 and u.kind == ROCK and Rect2(Vector2.ZERO, leaf.rect.size).has_point(
				cam.unproject_position(view_units.world_position(u.id))):
			rocks_in_view += 1
	check("double tap a unit: all your units of its type in the pane (%d)" % game.selection.size(),
			after_one == [rock0.id] and rocks_in_view > 1 and game.selection.size() == rocks_in_view
			and game.selection.all(func(id): return sim.get_unit(id).kind == ROCK))
	# Tap the HQ with units selected: they go gather.
	game._last_tap.camera = null
	sim._pending.clear()
	var hq_px: Vector2 = cam.unproject_position(Vector3(my_hq.x / 100.0, 6.0, my_hq.z / 100.0))
	game._on_tapped(cam, hq_px)
	queued = [] if sim._pending.is_empty() else sim._pending.values()[0]
	check("tapping the HQ with units selected sends them to gather", queued.size() == 1 and queued[0].type == "harvest")
	# An enemy hitting the HQ, standing on its picture: tapping it attacks it
	# (it doesn't count as tapping the HQ).
	sim._pending.clear()
	var hq_pic: Rect2 = buildings_view.screen_rect(cam, my_hq.id)
	var hq_raider_spot: Variant = cam.ground_at(hq_pic.get_center() + Vector2(0, hq_pic.size.y * 0.3))
	var hq_raider: int = sim.add_unit(1, ROCK, Vector2(hq_raider_spot.x, hq_raider_spot.z))
	await frames(1)
	var hq_raider_px: Vector2 = cam.unproject_position(view_units.world_position(hq_raider))
	check("(the enemy stands on the HQ's picture)", hq_pic.has_point(hq_raider_px))
	game._last_tap.camera = null
	game._on_tapped(cam, hq_raider_px)
	queued = [] if sim._pending.is_empty() else sim._pending.values()[0]
	check("tapping an enemy on your HQ attacks it, not the HQ", queued.size() == 1 and queued[0].type == "attack"
			and queued[0].target == hq_raider)
	sim._pending.clear()
	sim.units.erase(sim.get_unit(hq_raider))
	sim._by_id.erase(hq_raider)
	view_units.forget(hq_raider)
	# Double tap the damaged HQ: repair.
	sim._pending.clear()
	game._select([])
	my_hq.hp = my_hq.max_hp - 100
	game._on_tapped(cam, hq_px)
	game._on_tapped(cam, hq_px)
	queued = [] if sim._pending.is_empty() else sim._pending.values()[0]
	check("double tap a damaged building: repair call", queued.size() == 1 and queued[0].type == "repair"
			and queued[0].building == my_hq.id and "repair" in hud._toast.text)
	sim._pending.clear()
	my_hq.hp = my_hq.max_hp
	game._last_tap.camera = null
	game._select(mine.slice(0, 2))  # what the checks below expect
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
		var top := Vector3(n.x / 100.0, ResView.top_of(n) - 1.0, n.z / 100.0)
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
	check("every resource spot and tree is drawn, with no badge over it", res_view._views.size() == sim.nodes.size()
			and not res_view._views[nearest_metal.id].has("label")
			and res_view._views[nearest_metal.id].root.get_children().all(func(c): return not c is Label3D))
	# Tapping a tree in a forest gathers wood from that tree.
	var forest_tree: Dictionary = {}
	for n in sim.nodes:
		if n.tree and (forest_tree.is_empty() or SimScript._dist2(n, my_hq) < SimScript._dist2(forest_tree, my_hq)):
			forest_tree = n
	cam.target = Vector3(forest_tree.x / 100.0, 0, forest_tree.z / 100.0)
	cam.refit()
	game._on_tapped(cam, cam.unproject_position(Vector3(forest_tree.x / 100.0, 10.0, forest_tree.z / 100.0)))
	queued = [] if sim._pending.is_empty() else sim._pending.values()[0]
	check("tapping a forest tree sends units to cut it", queued.size() == 1 and queued[0].type == "gather"
			and queued[0].node == forest_tree.id)
	sim._pending.clear()
	# An emptied spot disappears.
	sim._remove_node(nearest_metal)
	sim._remove_node(forest_tree)
	res_view._sync()
	check("an emptied resource spot or cut tree goes away", not res_view._views.has(nearest_metal.id)
			and not res_view._views.has(forest_tree.id))
	sim._remove_building(sim.hq_of(1))
	await frames(2)
	check("destroying the enemy HQ shows the Victory sign", hud.game_over_screen.visible and hud._over_label.text == "Victory!"
			and hud._over_banner.visible and hud._over_banner.texture == hud.VICTORY)

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
