extends SceneTree
## Online play without the network: two copies of the game (one per player)
## swap their orders directly, encoded exactly as they would be online, and
## must stay identical. Also: waiting for the other player, and nobody can
## order the other side's units.
## Run: godot --headless -s res://tests/test_lockstep.gd

const SimScript := preload("res://scripts/sim/sim.gd")
const NetSession := preload("res://scripts/net/net_session.gd")
const ROCK := 0
const PAPER := 1
const SCISSORS := 2

var field: Node3D
var failures := 0


func _initialize() -> void:
	root.size = Vector2i(1920, 1200)
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


func player(team: int) -> Node:
	var s: Node = SimScript.new()
	s.field = field
	root.add_child(s)
	s.set_process(false)
	s.start_online(team)
	return s


## Wires two players together through the same encoding the network uses.
## `drop_from` = a seat whose messages get lost (to test waiting).
func connect_pair(a: Node, b: Node, link: Dictionary) -> void:
	for pair in [[a, b], [b, a]]:
		var from: Node = pair[0]
		var to: Node = pair[1]
		from.turn_ready.connect(func(at, cmds):
			if link.get("cut", -1) == from.local_team:
				return
			var wire: String = NetSession.encode_commands(cmds)
			to.receive_turn(at, from.local_team, NetSession.decode_commands(wire)))
		from.hash_ready.connect(func(at, h): to.receive_hash(at, from.local_team, h))
		from.desynced.connect(func(at): link.desync = at)


func run_both(a: Node, b: Node, ticks: int) -> void:
	for i in ticks:
		a._process(SimScript.TICK_TIME)
		b._process(SimScript.TICK_TIME)


func _run() -> void:
	await frames(5)
	field = root.get_node("Main/World/Field")
	root.get_node("Main/Sim").set_process(false)

	var a := player(0)
	var b := player(1)
	var link := {}
	connect_pair(a, b, link)
	check("both start from the same game", a.state_hash() == b.state_hash())

	# Each side orders its own army around; A also tries to move B's units.
	var reds: Array = a.units.filter(func(u): return u.team == 0).map(func(u): return u.id)
	var blues: Array = b.units.filter(func(u): return u.team == 1).map(func(u): return u.id)
	var centre := Vector3(410, 0, 410)
	a.command_attack_move(reds, centre + Vector3(-40, 0, -40))
	b.command_attack_move(blues, centre + Vector3(-40, 0, -40))
	a.command_move(blues, Vector3(100, 0, 100))  # not A's units: ignored
	run_both(a, b, 30)
	check("orders wait for the network delay, then run on both", a.tick == b.tick and a.tick == 30)
	var blue_unit: Dictionary = a.get_unit(blues[0])
	check("a player can't order the other side's units", absi(blue_unit.dest_x - 10000) > 10000)
	var hq_a: Dictionary = a.hq_of(0)
	a.command_build(1, "quarry", Vector2(hq_a.x, hq_a.z) / 100.0 + Vector2(25, -20))  # building for blue: ignored
	a.command_build(0, "quarry", Vector2(hq_a.x, hq_a.z) / 100.0 + Vector2(25, -20))
	run_both(a, b, 20)
	var quarries: Array = b.buildings.filter(func(q): return q.btype == "quarry")
	check("...or build for them (only red's own quarry went up)", quarries.size() == 1 and quarries[0].team == 0)
	run_both(a, b, 600)
	check("after 30 s of fighting both games are identical (tick %d)" % a.tick,
			a.state_hash() == b.state_hash() and a.units.size() == b.units.size())
	check("...and the fingerprints never disagreed", not link.has("desync"))

	# If the other player's orders don't arrive, the game waits.
	link.cut = 1
	var before: int = a.tick
	run_both(a, b, 40)
	check("no orders from the other player: the game waits (%d ticks on)" % (a.tick - before),
			a.tick - before <= SimScript.NET_DELAY + 1 and a.stalled)
	a.queue_free()
	b.queue_free()

	# Encoding: whole numbers stay whole, and nothing but plain data gets through.
	var cmds: Array = [{"type": "move", "ids": [5, 6], "x": 41000, "z": -3}]
	var back: Array = NetSession.decode_commands(NetSession.encode_commands(cmds))
	check("orders survive the trip exactly", back == cmds and typeof(back[0].ids[0]) == TYPE_INT)
	check("garbage from the network is ignored", NetSession.decode_commands("not base64!").is_empty())

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
