extends SceneTree
## A sleeping server (free hosting) takes a while to answer: the game keeps
## trying and says it's waking up, and only gives up after a while.
## Run: godot --headless -s res://tests/test_net_wake.gd

const NetSession := preload("res://scripts/net/net_session.gd")

var failures := 0


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): print("FAIL timed out"); quit(1))
	_run()


func _run() -> void:
	var net: Node = NetSession.new()
	root.add_child(net)
	var said := {"waking": 0, "failed": 0}
	net.waking.connect(func(): said.waking += 1)
	net.failed.connect(func(_m): said.failed += 1)
	net.connect_to("ws://127.0.0.1:18799")  # nothing listening there
	net.create_room()
	await create_timer(6.0).timeout
	check("no answer yet: says the server is waking up, once (%d)" % said.waking, said.waking == 1)
	check("...and keeps trying instead of failing", said.failed == 0)
	net._give_up_at = Time.get_ticks_msec()  # a minute has gone by
	await create_timer(4.0).timeout
	check("after the wait it gives up: can't reach the server", said.failed == 1)
	net.leave()
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
