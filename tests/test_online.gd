extends SceneTree
## Online play end to end: the real relay server (started by run_tests.sh,
## address in WH_SERVER), two start menus creating and joining a game by
## code, then two games in lockstep over the network. Skipped without Node.
## Run: tests/run_tests.sh (or WH_SERVER=ws://127.0.0.1:18766 godot --headless -s res://tests/test_online.gd)

const SimScript := preload("res://scripts/sim/sim.gd")
const NetSession := preload("res://scripts/net/net_session.gd")
const StartMenu := preload("res://scripts/start_menu.gd")

var field: Node3D
var failures := 0


func _initialize() -> void:
	root.size = Vector2i(1920, 1200)
	create_timer(200.0).timeout.connect(func(): print("FAIL timed out"); quit(1))
	root.add_child(load("res://scenes/main.tscn").instantiate())
	_run()


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


## Waits (a few seconds at most) until `done` returns true.
func until(done: Callable, seconds: float = 5.0) -> bool:
	var end: int = Time.get_ticks_msec() + int(seconds * 1000)
	while not done.call():
		if Time.get_ticks_msec() > end:
			return false
		await process_frame
	return true


func _run() -> void:
	var url: String = OS.get_environment("WH_SERVER")
	if url == "":
		print("SKIP no relay server (WH_SERVER not set)")
		print("FAILURES: 0")
		quit(0)
		return
	NetSession.url_override = url
	await frames(5)
	field = root.get_node("Main/World/Field")
	root.get_node("Main/Sim").set_process(false)

	# Two start menus: one creates a game, the other types the code.
	var menu_a: Control = StartMenu.new()
	var menu_b: Control = StartMenu.new()
	root.add_child(menu_a)
	root.add_child(menu_b)
	var got := {}
	menu_a.online_ready.connect(func(session, seat): got.a = [session, seat])
	menu_b.online_ready.connect(func(session, seat): got.b = [session, seat])
	check("the menu shows the version", menu_a._version_label.text.begins_with("version ")
			and not menu_a._update_button.visible)
	var MatchSetup = load("res://scripts/match_setup.gd")
	MatchSetup.map = "woods"  # the host picked Deep Woods
	menu_a._create()
	var shown: bool = await until(func(): return menu_a._wait_text.text.length() == 4)
	var code: String = menu_a._wait_text.text
	check("Create shows a 4-digit code (%s)" % code, shown and code.is_valid_int())
	for digit in code:
		menu_b._on_key(digit)
	check("the number pad types it", menu_b._typed == code)
	menu_b._on_key("Join")
	var both: bool = await until(func(): return got.has("a") and got.has("b"))
	check("joining starts the game for both, as red (0) and blue (1)", both and got.a[1] == 0 and got.b[1] == 1)
	if not both:
		print("FAILURES: ", failures + 1)
		quit(1)
		return
	check("the guest is told the host's map (%s)" % got.b[0].map, got.a[0].map == "woods" and got.b[0].map == "woods")
	MatchSetup.map = "island"
	menu_a.queue_free()
	menu_b.queue_free()

	# Two games in lockstep over the network.
	var sessions := [got.a[0], got.b[0]]
	var sims := []
	for i in 2:
		root.add_child(sessions[i])
		var s: Node = SimScript.new()
		s.field = field
		root.add_child(s)
		s.set_process(false)
		sessions[i].attach(s)
		sims.append(s)
	# Both say they're loaded (one later than the other): both get the go.
	var gos := [0, 0]
	sessions[0].both_ready.connect(func(): gos[0] += 1)
	sessions[1].both_ready.connect(func(): gos[1] += 1)
	sessions[0].mark_ready()
	await create_timer(0.5).timeout
	check("the first player to load waits for the other", gos[0] == 0)
	sessions[1].mark_ready()
	var together: bool = await until(func(): return gos[0] == 1 and gos[1] == 1)
	check("...and both start together once both have loaded", together)
	check("...with the same measured order delay (%d / %d ticks)" % [sims[0].net_delay, sims[1].net_delay],
			sims[0].net_delay == sims[1].net_delay and sims[0].net_delay >= 6 and sessions[0]._rtts.size() == NetSession.PINGS)
	var flags := {}
	for i in 2:
		sessions[i].desynced.connect(func(): flags.desync = true)
		sessions[i].opponent_left.connect(func(): flags["left_%d" % i] = true)
	var a: Node = sims[0]
	var b: Node = sims[1]
	var reds: Array = a.units.filter(func(u): return u.team == 0).map(func(u): return u.id)
	var blues: Array = b.units.filter(func(u): return u.team == 1).map(func(u): return u.id)
	a.command_attack_move(reds, Vector3(370, 0, 370))
	b.command_attack_move(blues, Vector3(370, 0, 370))
	var target_tick := 400
	var ran: bool = await until(func():
		a._process(SimScript.TICK_TIME)
		b._process(SimScript.TICK_TIME)
		return a.tick >= target_tick and b.tick >= target_tick, 60.0)
	check("both games run over the network (ticks %d / %d)" % [a.tick, b.tick], ran)
	# Bring them to the same tick, then compare.
	while a.tick < b.tick:
		a._process(SimScript.TICK_TIME)
		await process_frame
	while b.tick < a.tick:
		b._process(SimScript.TICK_TIME)
		await process_frame
	check("...and stay identical (armies met: %d units left)" % a.units.size(),
			a.state_hash() == b.state_hash() and a.units.size() < 24)
	check("...fingerprints agreed all along", not flags.has("desync"))

	# One player leaves: the other is told.
	sessions[0].leave()
	var told: bool = await until(func(): return flags.has("left_1"))
	check("when one player leaves, the other is told", told)

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
