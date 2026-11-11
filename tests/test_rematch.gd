extends SceneTree
## End screen: Rematch and Quit to menu. vs Computer, Rematch restarts the
## same match at once; online, the other player is asked first, both
## restart when both agree, and it's masked out if they left. Orders from
## the last match never leak into the next.
## Run: godot --headless -s res://tests/test_rematch.gd

const MatchSetup := preload("res://scripts/match_setup.gd")
const NetSession := preload("res://scripts/net/net_session.gd")
const SimScript := preload("res://scripts/sim/sim.gd")

var failures := 0


func _initialize() -> void:
	root.size = Vector2i(1920, 1200)
	create_timer(90.0).timeout.connect(func(): print("FAIL timed out"); quit(1))
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


func _run() -> void:
	await frames(3)
	var game: Node = root.get_node("Main/Game")
	game._begin("computer")
	await frames(1)
	game.sim.set_process(false)
	game.hud.show_game_over(1 - game.player_team)
	var hud: Control = game.hud
	check("the end screen has Rematch and Quit to menu", hud.rematch_button.visible and hud.quit_button.visible
			and hud.rematch_button.text == "Rematch" and hud.quit_button.text == "Quit to menu")

	# vs Computer: Rematch starts the same match again right away.
	hud.rematch_button.pressed.emit()
	await frames(4)
	var game2: Node = root.get_node("Main/Game")
	check("Rematch (vs Computer) starts a fresh match: no menu, countdown", game2 != game and game2.mode == "computer"
			and is_instance_valid(game2.countdown_layer) and not game2.hud.game_over_screen.visible)

	# Quit to menu: back to the start.
	game2.hud.quit_button.pressed.emit()
	await frames(4)
	var game3: Node = root.get_node("Main/Game")
	check("Quit to menu reloads with nothing waiting", game3 != game2 and game3.mode == "" and MatchSetup.pending.is_empty())

	# Online: the rematch handshake.
	var a: Node = NetSession.new()
	var b: Node = NetSession.new()
	a.seat = 0
	b.seat = 1
	var got := {"a_asked": 0, "b_asked": 0, "a_go": 0, "b_go": 0}
	a.rematch_requested.connect(func(): got.a_asked += 1)
	b.rematch_requested.connect(func(): got.b_asked += 1)
	a.rematch_agreed.connect(func(): got.a_go += 1)
	b.rematch_agreed.connect(func(): got.b_go += 1)
	a.request_rematch()
	var sent: Dictionary = a._waiting.back()
	check("asking sends a rematch request", sent.t == "rematch")
	b._handle(JSON.stringify(sent))
	check("...the other player is told", got.b_asked == 1 and got.a_go == 0 and got.b_go == 0)
	b.request_rematch()
	a._handle(JSON.stringify(b._waiting.back()))
	check("...and when they accept, both restart", got.a_go == 1 and got.b_go == 1)
	a.reset_for_rematch()
	b.reset_for_rematch()
	# A stray order from the last match arrives late: dropped.
	var s: Node = SimScript.new()
	s.field = root.get_node("Main/World/Field")
	root.add_child(s)
	s.set_process(false)
	b.attach(s)
	b._handle(JSON.stringify({"t": "turn", "tick": 7, "seat": 0, "g": 0,
			"c": NetSession.encode_commands([{"type": "hold", "ids": [1]}])}))
	check("orders from the last match are ignored in the new one", not s._turns.has(7) and b.game_no == 1)
	b._handle(JSON.stringify({"t": "turn", "tick": 8, "seat": 0, "g": 1,
			"c": NetSession.encode_commands([])}))
	check("...the new match's orders get through", s._turns.has(8))

	# They left: masked out.
	var c: Node = NetSession.new()
	c.seat = 0
	c._handle(JSON.stringify({"t": "left"}))
	c.request_rematch()
	check("after the other player leaves, no rematch can be asked", c._waiting.is_empty())
	game3.hud.show_game_over(0)
	game3.hud.set_rematch_state("gone")
	check("...and the button is masked out", game3.hud.rematch_button.disabled and "left" in game3.hud.rematch_note.text)
	game3.hud.set_rematch_state("offered")
	check("an incoming request shows on the end screen", game3.hud.rematch_button.text == "Accept rematch"
			and "rematch" in game3.hud.rematch_note.text)

	for n in [a, b, c]:
		n.free()
	MatchSetup.pending = {}
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
