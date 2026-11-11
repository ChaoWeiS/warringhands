extends SceneTree
## Cancelling a building still going up (all the cost back), selling a
## finished one (half back, plus any queued units), never your last HQ, and
## the panel's Cancel / Sell button (tap, then "Sure?", then tap again).
## Run: godot --headless -s res://tests/test_sell.gd

const SimScript := preload("res://scripts/sim/sim.gd")

var failures := 0


func _initialize() -> void:
	root.size = Vector2i(1920, 1200)
	create_timer(60.0).timeout.connect(func(): print("FAIL timed out"); quit(1))
	root.add_child(load("res://scenes/main.tscn").instantiate())
	_run()


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


## An open spot near the team's HQ for a quarry.
func spot(sim: Node, team: int, skip: Array = []) -> Vector2:
	var home: Dictionary = sim.hq_of(team)
	for ring in [30.0, 36.0, 42.0]:
		for k in 16:
			var p: Vector2 = Vector2(home.x, home.z) / 100.0 + Vector2.from_angle(k * TAU / 16) * ring
			if sim.can_place("quarry", p, team) and skip.all(func(q): return q.distance_to(p) > 20.0):
				return p
	return Vector2.ZERO


func newest(sim: Node, team: int, btype: String) -> Dictionary:
	var found: Array = sim.buildings.filter(func(b): return b.team == team and b.btype == btype)
	return {} if found.is_empty() else found.back()


func _run() -> void:
	await frames(3)
	var game: Node = root.get_node("Main/Game")
	var sim: Node = root.get_node("Main/Sim")
	var hud: Node = game.hud
	sim.set_process(false)
	sim._ais.clear()
	sim.clear_units()
	var cost: int = SimScript.BUILDINGS.quarry.cost
	sim.resources[0] = [500, 500, 500]

	# Cancel while it's going up: every stone back.
	var p1: Vector2 = spot(sim, 0)
	sim.command_build(0, "quarry", p1)
	sim.step_ticks(3)
	var q1: Dictionary = newest(sim, 0, "quarry")
	check("(a quarry is going up, %d stone paid)" % cost, not q1.is_empty() and q1.progress < SimScript.BUILDINGS.quarry.build
			and sim.resources[0][0] == 500 - cost)
	sim.command_sell(0, [q1.id])
	sim.step_ticks(3)
	check("cancelling it removes it", sim.get_entity(q1.id).is_empty())
	check("...and gives all the stone back", sim.resources[0][0] == 500)
	check("...and frees the ground", sim.can_place("quarry", p1, 0))

	# Sell a finished one with two units queued: half back, plus the units.
	sim.command_build(0, "quarry", p1)
	sim.step_ticks(3)
	var q2: Dictionary = newest(sim, 0, "quarry")
	q2.progress = SimScript.BUILDINGS.quarry.build
	sim.command_train(0, q2.id)
	sim.command_train(0, q2.id)
	sim.step_ticks(3)
	var before: int = sim.resources[0][0]
	check("(it's finished, two units queued)", q2.queue.size() == 2)
	sim.command_sell(0, [q2.id])
	sim.step_ticks(3)
	var expected: int = cost * SimScript.SELL_REFUND / 100 + 2 * SimScript.UNIT_COST
	check("selling a finished building gives half its cost back, plus queued units (+%d)" % (sim.resources[0][0] - before),
			sim.get_entity(q2.id).is_empty() and sim.resources[0][0] == before + expected)

	# Your only HQ stays; with a second one, either can go.
	var hq: Dictionary = sim.hq_of(0)
	sim.command_sell(0, [hq.id])
	sim.step_ticks(3)
	check("your last HQ can't be sold", not sim.get_entity(hq.id).is_empty() and sim.winner < 0)
	check("...and its panel doesn't offer it", not sim.can_sell(hq))

	# The other side can't sell your buildings (online orders carry a seat).
	sim.command_build(0, "quarry", p1)
	sim.step_ticks(3)
	var q3: Dictionary = newest(sim, 0, "quarry")
	sim._apply({"type": "sell", "team": 0, "ids_b": [q3.id], "by": 1})
	check("the other player can't sell your buildings", not sim.get_entity(q3.id).is_empty())
	sim._apply({"type": "sell", "team": 1, "ids_b": [q3.id], "by": 1})
	check("...not even naming their own side", not sim.get_entity(q3.id).is_empty())

	# The panel: Cancel on one going up; first tap asks, second does it.
	game._select_buildings([q3.id])
	hud._process(0.0)
	var row: Dictionary = hud._rows.get("quarry", {})
	check("a building going up shows a Cancel button", not row.is_empty() and row.sell.visible
			and row.sell_key.begins_with("Cancel %d" % cost))
	sim._pending.clear()
	row.sell.pressed.emit()
	hud._process(0.0)
	check("one tap only asks \"Sure?\"", sim._pending.is_empty() and row.sell_key.begins_with("Sure?"))
	row.sell.pressed.emit()
	var queued: Array = [] if sim._pending.is_empty() else sim._pending.values()[0]
	check("a second tap cancels it", queued.size() == 1 and queued[0].type == "sell" and queued[0].ids_b == [q3.id])
	sim.step_ticks(3)
	await frames(1)
	check("...and it's gone and deselected", sim.get_entity(q3.id).is_empty() and not game.selected_buildings.has(q3.id))

	# A finished one says Sell (half); the HQ row has no button.
	sim.command_build(0, "quarry", p1)
	sim.step_ticks(3)
	var q4: Dictionary = newest(sim, 0, "quarry")
	q4.progress = SimScript.BUILDINGS.quarry.build
	game._select_buildings([q4.id, hq.id])
	hud._process(0.0)
	check("a finished building shows Sell, for half", hud._rows.quarry.sell.visible
			and hud._rows.quarry.sell_key == "Sell %d" % (cost * SimScript.SELL_REFUND / 100))
	check("your only HQ has no Sell button", not hud._rows.hq.sell.visible)

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
