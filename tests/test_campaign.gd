extends SceneTree
## The campaign: the chapter list on the start menu, and every chapter
## played through to the end (orders given as the player would, the
## simulation stepped by hand). Arrows point where they should.
## Run: godot --headless -s res://tests/test_campaign.gd

const Campaign := preload("res://scripts/campaign.gd")
const MatchSetup := preload("res://scripts/match_setup.gd")

var failures := 0
var game: Node
var sim: Node
var panes: Control
var tut: Control


func _initialize() -> void:
	root.size = Vector2i(1920, 1200)
	create_timer(300.0).timeout.connect(func(): print("FAIL timed out"); quit(1))
	_run()


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


## A fresh game showing the start menu (the previous one thrown away).
func fresh() -> Control:
	if root.has_node("Main"):
		var old: Node = root.get_node("Main")
		root.remove_child(old)
		old.free()
	root.add_child(load("res://scenes/main.tscn").instantiate())
	await frames(3)
	game = root.get_node("Main/Game")
	sim = root.get_node("Main/Sim")
	panes = root.get_node("Main/Panes")
	for c in root.get_node("Main/HUD").get_children():
		if c.has_signal("vs_computer"):
			return c
	return null


## Starts chapter i in a fresh game (sim stepped by the test).
func play(i: int) -> void:
	MatchSetup.map = Campaign.map_of(i)
	var menu: Control = await fresh()
	if menu != null:
		menu.queue_free()
	tut = game.start_tutorial(i)
	sim.set_process(false)
	await frames(2)


func mine(kind: int = -1) -> Array:
	return sim.units.filter(func(u): return u.team == 0 and (kind < 0 or u.kind == kind)).map(func(u): return u.id)


## Steps the simulation (and frames, for the polls) until the tutorial
## leaves `at`, or gives up.
func until_past(at: int, ticks: int) -> bool:
	for t in ticks / 10:
		sim.step_ticks(10)
		await process_frame
		if tut.step != at:
			return true
	return tut.step != at


## Builds the lesson's factory where its arrow points (again if a gatherer
## was in the way), until the step moves on.
func build_beside(res: int) -> bool:
	var at: int = tut.step
	for attempt in 20:
		sim.command_build(0, ["quarry", "mill", "forge"][res], tut._build_at[res])
		if await until_past(at, 20):
			return true
	return false


func pointing(what: String) -> bool:
	return not tut._resolve(what).is_empty()


func _run() -> void:
	# The start menu: Campaign, with every chapter listed.
	await fresh()
	var menu: Control = load("res://scripts/start_menu.gd").new()
	root.get_node("Main/HUD").add_child(menu)
	await frames(1)
	check("the start menu has Campaign instead of Tutorial", menu._main.get_child(0).text == "Campaign")
	menu._open_campaign()
	await frames(1)
	check("Campaign lists the %d chapters" % Campaign.CHAPTERS.size(),
			menu._chapters.visible and menu.chapter_button(Campaign.CHAPTERS.size() - 1) != null)
	var picked := [-1]
	menu.tutorial.connect(func(i): picked[0] = i)
	menu.chapter_button(2).pressed.emit()
	check("tapping a chapter plays it", picked[0] == 2)
	var battle := [false]
	menu.vs_computer.connect(func(): battle[0] = true)
	menu._skip_campaign.pressed.emit()
	check("Skip tutorial goes straight to a battle on the main island", battle[0] and MatchSetup.map == "island")
	menu.queue_free()

	# --- 1. Getting around -----------------------------------------------------
	await play(0)
	check("chapter 1 opens by suggesting landscape", "landscape" in tut._text.text and tut._skip.text == "Next")
	tut._quit.pressed.emit()
	await frames(1)
	var left := [false]
	tut.finished.connect(func(): left[0] = true)
	check("Menu asks first (no leaving by accident)", is_instance_valid(tut._leave_dialog) and not left[0])
	tut._leave_dialog.queue_free()
	await frames(1)
	check("the lessons play on the small training island", sim.field.map_id == "training" and sim.field.island_radius < 200)
	game._select(mine())
	await frames(2)
	check("...showing only what's been taught: no hammer, sword, Hold, Queue or screen cutting yet",
			not game.hud._build_toggle.visible and not game.bar._attack.visible
			and not game.bar.actions.get_child(1).visible and not game.bar.queue_button.visible and not panes.cutting)
	game._select([])
	var cam_home: Camera3D = panes._leaves()[0].camera
	var hq0: Dictionary = sim.hq_of(0)
	check("the camera frames your base (HQ on screen)",
			panes._leaves()[0].rect.has_point(cam_home.unproject_position(Vector3(hq0.x / 100.0, 0, hq0.z / 100.0))))
	tut._skip.pressed.emit()
	check("...then shows the HQ, with a picture and an arrow on it",
			"HQ" in tut._text.text and tut._picture_slot.get_child_count() == 1 and pointing("hq"))
	await frames(30)
	check("...and a spotlight on it: the rest of the screen dims", tut._dim > 0.2 and tut._holes.size() >= 1)
	tut._skip.pressed.emit()
	await frames(1)
	check("a step to do has no Skip at first (finish it to move on)", not tut._skip.visible)
	tut._step_time = tut.SKIP_AFTER + 1.0
	await frames(1)
	check("...but Skip appears after a minute, in case someone's stuck", tut._skip.visible)
	var cam: Camera3D = panes._leaves()[0].camera
	cam.target += Vector3(20, 0, 0)
	await frames(2)
	check("dragging the camera moves on to zooming", "pinch" in tut._text.text)
	cam.units_per_pixel *= 1.5
	await frames(2)
	check("zooming moves on to the minimap, with an arrow at it", "minimap" in tut._text.text and pointing("ui:minimap"))
	cam.target += Vector3(120, 0, 0)
	await frames(2)
	check("jumping somewhere moves on to picking a hand (camera back home, arrow on a rock)",
			"Tap one" in tut._text.text and pointing("kind:0")
			and Vector2(cam.target.x, cam.target.z).distance_to(Vector2(sim.hq_of(0).x, sim.hq_of(0).z) / 100.0) < 60)
	game._select(mine())
	game.did.emit("select")
	await frames(30)
	check("the Group step lights up the Group button AND your hands (with a dashed loop to copy)",
			pointing("ui:group") and pointing("army") and tut._holes.size() >= 2)
	panes.grouping = true
	await frames(1)
	check("...holding Group, the card says what to do next", "Keep holding Group" in tut._text.text)
	panes.grouping = false
	await frames(1)
	check("Back to Menu sits at the bottom left of the card", tut._quit.text == "Back to Menu"
			and tut._quit.get_index() == 0 and tut._quit.get_global_rect().position.x < tut._skip.get_global_rect().position.x)
	game.did.emit("lasso")
	check("moving: a circle to send them to (not just anywhere)", tut._marked.size() == 1 and pointing("mark:0"))
	game.did.emit("move")
	check("...a move elsewhere doesn't count", "circle" in tut._text.text)
	sim.command_move(mine(), Vector3(tut._marked[0].x, 0, tut._marked[0].y))
	check("...getting there does", await until_past(tut.step, 600))
	game.did.emit("select_kind")
	game._unselect_all()
	check("select, loop, move, double tap and unselect finish the chapter",
			tut._is_end() and 0 in Campaign.done() and tut._next_chapter.visible)

	# --- 2. Rock, paper, scissors ------------------------------------------------
	await play(1)
	check("chapter 2 shows the rock-paper-scissors circle", tut._picture_slot.get_child_count() == 1)
	tut._skip.pressed.emit()
	await frames(30)
	check("the spotlight shines on all your rocks (a double tap picks them all), not just one",
			tut._holes.size() >= mine(0).size() + 1)
	check("enemy scissors arrive (three, waiting) and the arrows point at your rocks and them",
			tut._enemies.size() == 3 and tut._enemies.all(func(id): return sim.get_unit(id).kind == 2)
			and pointing("kind:0") and pointing("enemies"))
	sim.step_ticks(100)
	check("they wait out of your army's sight: no fight starts until you send hands",
			tut._enemies.all(func(id): return sim.get_unit(id).hp == 100))
	var e0: Dictionary = sim.get_unit(tut._enemies[0])
	check("...and the camera shows them", panes._leaves()[0].rect.has_point(
			panes._leaves()[0].camera.unproject_position(Vector3(e0.x / 100.0, 0, e0.z / 100.0))))
	for kind in [0, 2, 1]:
		var at: int = tut.step
		for id in tut._enemies:
			sim.command_attack(mine(kind), id, true)
		check("beating them with the right hand moves on (step %d)" % at, await until_past(at, 1500))
	game._select(mine())
	await frames(2)
	check("the mixed group points at the sword button, and the Group button to select them all",
			tut._enemies.size() == 6 and pointing("ui:attack") and pointing("ui:group"))
	var e: Dictionary = sim.get_unit(tut._enemies[0])
	sim.command_attack_move(mine(), Vector3(e.x / 100.0, 0, e.z / 100.0))
	check("...and beating it finishes the chapter", await until_past(tut.step, 3000) and tut._is_end())

	# --- 3. Resources and factories ----------------------------------------------
	await play(2)
	check("the hammer shows from the factories chapter on (but not the HQ option yet)",
			game.hud._build_toggle.visible and not game.hud._build_options.hq.visible)
	check("chapter 3 puts a stone pile, lumber camp and crystals near your HQ, each with room for its factory",
			tut._spots.all(func(n): return not n.is_empty()) and not Vector2.INF in tut._build_at)
	check("it points at the resource counter", pointing("ui:resources"))
	tut._skip.pressed.emit()
	sim.command_gather(mine(0), tut._spots[0].id)
	check("sending rocks to the stone pile moves on", await until_past(1, 100))
	check("...and the stone reaching the HQ moves on", await until_past(2, 1500))
	var cam3: Camera3D = panes._leaves()[0].camera
	cam3.target += Vector3(150, 0, 90)  # the player wandered off
	cam3.refit()
	tut._skip.pressed.emit()
	await create_timer(1.2).timeout
	var spot0: Vector2 = tut._build_at[0]
	check("a new step brings the camera back to what it's about",
			panes._leaves()[0].rect.has_point(cam3.unproject_position(Vector3(spot0.x, 0, spot0.y))))
	check("building a Quarry: arrows at the hammer and the spot beside the pile", pointing("ui:build:quarry") and pointing("spot:0"))
	check("a Quarry beside the pile moves on", await build_beside(0))
	check("stone dropped at the Quarry moves on", await until_past(5, 2500))
	for res in [1, 2]:
		sim.command_gather(mine(res), tut._spots[res].id)
		check("sending the %s gatherers moves on" % ["", "papers", "scissors"][res], await until_past(tut.step, 100))
		check("building its factory beside it moves on", await build_beside(res))
	check("chapter 3 done", tut._is_end() and 2 in Campaign.done())

	# --- 4. Making hands ----------------------------------------------------------
	await play(3)
	var factories: Dictionary = {}
	for b in sim.buildings:
		if b.team == 0:
			factories[b.btype] = b
	sim.step_ticks(5)
	check("chapter 4 starts with a finished Quarry, Paper Mill and Forge, everyone gathering",
			factories.has("quarry") and factories.has("mill") and factories.has("forge")
			and sim.units.filter(func(u): return u.team == 0 and u.job == "gather").size() == 12)
	sim.command_train(0, factories.quarry.id)
	game.did.emit("train")
	check("training a rock: wait for it to walk out", await until_past(1, 300))
	sim.command_train(0, factories.mill.id)
	sim.command_train(0, factories.forge.id)
	check("a new paper and scissors move on", await until_past(2, 300))
	tut._skip.pressed.emit()
	check("a raid comes (marching, not waiting)", tut._enemies.size() == 3 and not sim.get_unit(tut._enemies[0]).hold)
	await frames(40)
	check("...no spotlight here (you need to see your hands to loop them), and an arrow at the Group button",
			tut._dim < 0.05 and pointing("ui:group"))
	var raid: Dictionary = sim.get_unit(tut._enemies[0])
	sim.command_attack_move(mine(), Vector3(raid.x / 100.0, 0, raid.z / 100.0))
	check("beating it moves on", await until_past(4, 2000))
	game.did.emit("harvest")
	check("sending them back to work finishes the chapter", tut._is_end())

	# --- 5. Repairs -----------------------------------------------------------------
	await play(4)
	var mill: Dictionary = {}
	for b in sim.buildings:
		if b.team == 0 and b.btype == "mill":
			mill = b
	check("chapter 5: the Paper Mill is damaged, with an arrow on it", mill.hp < mill.max_hp and pointing("building:mill"))
	tut._skip.pressed.emit()
	sim.step_ticks(200)  # gatherers out at work, near the mill
	sim.command_repair(0, mill.id)
	game.did.emit("repair")
	check("repairing it: wait until it's whole", await until_past(2, 3000) and mill.hp == mill.max_hp)
	tut._skip.pressed.emit()
	check("chapter 5 done", tut._is_end())

	# --- 6. Battle tricks -----------------------------------------------------------
	await play(5)
	game._select(mine())
	await frames(2)
	check("first, a circle to send your hands to", pointing("mark:0"))
	sim.command_move(mine(), Vector3(tut._marked[0].x, 0, tut._marked[0].y))
	check("...getting there moves on to Hold", await until_past(tut.step, 600))
	check("Hold, with an arrow at its button", pointing("ui:hold"))
	game.did.emit("hold")
	check("Queue: three numbered circles to go through in order", tut._marked.size() == 3
			and tut._resolve("mark:1").get("label", "") == "2")
	var route: Array = tut._marked.duplicate()
	var queue_step: int = tut.step
	sim.command_move(mine(), Vector3(route[0].x, 0, route[0].y))
	sim.command_move(mine(), Vector3(route[1].x, 0, route[1].y), true)
	sim.command_move(mine(), Vector3(route[2].x, 0, route[2].y), true)
	game.did.emit("queue")
	check("walking the route, 1 then 2 then 3, moves on", await until_past(queue_step, 1500))
	panes._split_leaf(panes._leaves()[0], true, 0.5)
	await frames(2)
	check("splitting moves on to merging", "merge" in tut._text.text)
	var split = panes._splits()[0]
	panes._merge(split, panes._leaves()[0])
	await frames(2)
	check("merging finishes the chapter", tut._is_end())

	# --- 7. First battle -------------------------------------------------------------
	await play(6)
	check("the battle: the computer plays the other side, with its army",
			sim.ai_of(1) != null and sim.units.any(func(u): return u.team == 1))
	tut._skip.pressed.emit()
	check("the card tucks away during the battle", tut.free_play and not tut._text.visible)
	sim.winner = 0
	await frames(2)
	check("winning completes the campaign", tut._is_end() and "Campaign complete" in tut._text.text
			and not tut._next_chapter.visible and 6 in Campaign.done())

	# Next chapter / Menu.
	await play(0)
	var next := [-1]
	tut.next_chapter.connect(func(i): next[0] = i)
	tut._next_chapter.pressed.emit()
	check("Next chapter asks for the next one", next[0] == 1)

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
