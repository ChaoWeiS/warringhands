extends SceneTree
## Surrender: a white flag by Settings asks first; confirming loses the game
## (the other side wins), "Keep playing" doesn't. Not in the tutorial.
## Run: godot --headless -s res://tests/test_surrender.gd

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


func _run() -> void:
	await frames(3)
	var game: Node = root.get_node("Main/Game")
	var sim: Node = root.get_node("Main/Sim")
	var panes: Control = root.get_node("Main/Panes")
	var hud: Control = game.hud
	sim.set_process(false)
	var flag: Button = hud.surrender_button
	var gear: Button = hud.settings_button
	check("there's a white flag button just left of Settings", flag.visible
			and absf(flag.get_global_rect().end.x + 12 - gear.get_global_rect().position.x) < 2
			and absf(flag.get_global_rect().position.y - gear.get_global_rect().position.y) < 2)

	flag.pressed.emit()
	await frames(1)
	check("pressing it asks first", is_instance_valid(hud.surrender_dialog) and hud.surrender_dialog.visible
			and sim.winner < 0)
	check("...and the map ignores touches while it asks", panes._blocked(Vector2(300, 900)))
	hud.surrender_dialog.get_meta("keep").pressed.emit()
	await frames(1)
	check("Keep playing closes it and nothing happens", not is_instance_valid(hud.surrender_dialog) and sim.winner < 0
			and not panes._blocked(Vector2(300, 900)))

	flag.pressed.emit()
	await frames(1)
	sim._pending.clear()
	hud.surrender_dialog.get_meta("give_up").pressed.emit()
	sim.step_ticks(4)
	await frames(1)
	check("Surrender loses the game: the other side wins", sim.winner == 1 - game.player_team)
	check("...and shows the Defeat sign", hud.game_over_screen.visible and hud._over_label.text == "Defeat"
			and hud._over_banner.visible and hud._over_banner.texture == hud.DEFEAT and not hud._over_label.visible)
	check("...and the flag goes away", not flag.visible)

	# Online, nobody can surrender for the other player.
	sim.winner = -1
	sim._apply({"type": "surrender", "team": 0, "by": 1})
	check("the other player can't surrender for you", sim.winner == -1)

	# The tutorial has Quit instead.
	hud.surrender_button.visible = true
	game.start_tutorial()
	await frames(1)
	check("no flag in the tutorial", not hud.surrender_button.visible)

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
