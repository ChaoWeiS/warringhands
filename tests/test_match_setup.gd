extends SceneTree
## Before a match: Play vs Computer picks a map and a difficulty, then a
## 3-2-1 countdown; another map reloads the scene with that island and starts
## the match there. Online: the host picks the map; the guest's orders that
## arrive early are kept.
## Run: godot --headless -s res://tests/test_match_setup.gd

const MatchSetup := preload("res://scripts/match_setup.gd")
const Settings := preload("res://scripts/settings.gd")
const NetSession := preload("res://scripts/net/net_session.gd")
const SimScript := preload("res://scripts/sim/sim.gd")

var failures := 0


func _initialize() -> void:
	root.size = Vector2i(1920, 1200)
	create_timer(120.0).timeout.connect(func(): print("FAIL timed out"); quit(1))
	MatchSetup.map = "island"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run()


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _menu() -> Control:
	return root.get_node("Main/HUD").get_children().filter(func(c): return c.has_signal("vs_computer")).front()


func _run() -> void:
	await frames(3)
	var game: Node = root.get_node("Main/Game")
	game._show_start_menu()
	await frames(1)
	var menu: Control = _menu()

	# Play vs Computer: the setup screen.
	menu._open_setup("computer")
	await frames(1)
	check("Play vs Computer shows the maps (%d) and the difficulty" % menu._map_cards.size(),
			menu._setup.visible and menu._map_cards.size() >= 3 and menu._difficulty_row.visible)
	menu._pick_difficulty("hard")
	check("the difficulty is remembered", MatchSetup.difficulty == "hard" and Settings.get_choice("difficulty", "") == "hard")
	menu._open_setup("online")
	check("Create Online Game shows the maps but no difficulty", menu._setup.visible and not menu._difficulty_row.visible
			and menu._setup_go.text == "Create")
	menu._open_setup("computer")
	menu._pick_map("island")

	# Same map: the countdown, then the game moves; the computer plays hard.
	menu._setup_go.pressed.emit()
	await frames(2)
	var sim: Node = root.get_node("Main/Sim")
	check("Start shows a countdown and the game waits", is_instance_valid(game.countdown_layer)
			and not sim.is_processing())
	var label: Label = game.countdown_layer.get_child(0)
	check("...starting at 3", label.text == "3")
	await create_timer(1.0).timeout
	check("...then 2", label.text == "2")
	await create_timer(1.7).timeout
	check("...then the game starts with Fight!", sim.is_processing() and label.text == "Fight!")
	check("...against a hard computer (with its head start)", sim.ai_of(1) != null and sim.ai_of(1).level == "hard"
			and sim.resources[1][0] >= sim.START_RESOURCES + 200)

	# Another map: the scene reloads with that island and the match starts.
	sim.set_process(false)
	MatchSetup.map = "pass"
	MatchSetup.difficulty = "easy"
	game._begin("computer")
	await frames(6)
	var field: Node = root.get_node("Main/World/Field")
	var game2: Node = root.get_node("Main/Game")
	check("picking Twin Lakes reloads with that island", game2 != game and field.map_id == "pass"
			and MatchSetup.built_map == "pass")
	check("...and the match starts there, no menu (countdown up)", is_instance_valid(game2.countdown_layer)
			and _menu_count() == 0)
	var sim2: Node = root.get_node("Main/Sim")
	check("...with an easy computer", sim2.ai_of(1) != null and sim2.ai_of(1).level == "easy")
	var hq: Dictionary = sim2.hq_of(0)
	check("...and the HQ where that map puts it", Vector2(hq.x, hq.z) / 100.0 == field.get_center() + Vector2(field.hq_offset))

	# Online: the guest waits for the host's map; early orders are kept.
	var guest: Node = NetSession.new()
	var started := [false]
	guest.started.connect(func(_s): started[0] = true)
	guest._handle(JSON.stringify({"t": "start", "seat": 1, "code": "1234"}))
	check("online: the guest waits for the host's map", not started[0])
	guest._handle(JSON.stringify({"t": "setup", "map": "woods", "seat": 0}))
	check("...then starts on it", started[0] and guest.map == "woods")
	var turn := {"t": "turn", "tick": 6, "seat": 0, "c": NetSession.encode_commands([{"type": "hold", "ids": [1]}])}
	guest._handle(JSON.stringify(turn))
	var s: Node = SimScript.new()
	s.field = field
	root.add_child(s)
	s.set_process(false)
	guest.attach(s)
	check("...and orders that came before the game was ready aren't lost", s._turns.has(6))
	# Starting together: nobody counts down until both have loaded.
	var go := [0]
	guest.both_ready.connect(func(): go[0] += 1)
	guest.mark_ready()
	check("online: loaded first, we wait for the other player", go[0] == 0 and not guest.is_both_ready())
	guest._handle(JSON.stringify({"t": "ready", "seat": 0}))
	check("...and both start when they're loaded too (once)", go[0] == 1)
	guest._handle(JSON.stringify({"t": "ready", "seat": 0}))
	check("...not twice", go[0] == 1)
	guest.free()

	MatchSetup.map = "island"
	MatchSetup.difficulty = "normal"
	Settings.set_choice("difficulty", "normal")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)


func _menu_count() -> int:
	return root.get_node("Main/HUD").get_children().filter(func(c): return c.has_signal("vs_computer")).size()
