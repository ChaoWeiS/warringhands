extends SceneTree
## Unit voices: every selected unit answers, orders get confirmed, and
## fights on screen make attack / defend / death sounds (off screen: quiet).
## Run: godot --headless -s res://tests/test_sounds.gd

const SimScript := preload("res://scripts/sim/sim.gd")

var failures := 0


func _initialize() -> void:
	root.size = Vector2i(1920, 1200)
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


func count(log: Array, from: int, category: String) -> int:
	return log.slice(from).filter(func(c): return c == category).size()


func _run() -> void:
	await frames(5)
	var game: Node = root.get_node("Main/Game")
	var sim: Node = root.get_node("Main/Sim")
	var view: Node3D = root.get_node("Main/World/Units")
	var panes: Control = root.get_node("Main/Panes")
	sim.set_process(false)
	sim._ais.clear()
	var sounds: Node = game.sounds
	var leaf = panes._leaves()[0]
	var cam = leaf.camera
	game.focus_home()
	await frames(2)

	# Every unit in a loop answers.
	var mine: Array = sim.units.filter(func(u): return u.team == 0).map(func(u): return u.id)
	var box := Rect2(cam.unproject_position(view.world_position(mine[0])), Vector2.ZERO)
	for id in mine.slice(0, 5):
		box = box.expand(cam.unproject_position(view.world_position(id)))
	var before: int = sounds.played.size()
	game._on_lassoed(cam, PackedVector2Array([box.position - Vector2(20, 20), Vector2(box.end.x + 20, box.position.y - 20),
			box.end + Vector2(20, 20), Vector2(box.position.x - 20, box.end.y + 20)]))
	check("every selected unit answers (%d units, %d answers)" % [game.selection.size(), count(sounds.played, before, "acknowledge")],
			game.selection.size() >= 2 and count(sounds.played, before, "acknowledge") == mini(game.selection.size(), sounds.MAX_CHORUS))
	var lines: Array = sounds.played_clips.slice(before)
	check("...all saying the same line", lines.size() >= 2 and lines.all(func(c): return c == lines[0]))
	before = sounds.played.size()
	game._last_tap.camera = null
	var hq: Dictionary = sim.hq_of(0)
	game._on_tapped(cam, cam.unproject_position(Vector3(hq.x / 100.0 + 30, 0, hq.z / 100.0 + 25)))
	check("an order gets a confirmation from each of them", count(sounds.played, before, "objective") == game.selection.size())
	await create_timer(0.3).timeout
	var at_once := 0
	for p in sounds._voices:
		if p.playing:
			at_once += 1
	check("...playing at the same time (%d voices)" % at_once, at_once >= 2)

	# A duel on screen: swings, cries, and a death.
	sim.clear_units()
	var centre := Vector2(cam.target.x, cam.target.z)
	var a: int = sim.add_unit(0, 0, centre + Vector2(-3.4, 0))
	var b: int = sim.add_unit(1, 2, centre + Vector2(3.4, 0))
	sim.get_unit(b).hp = 30
	await frames(2)
	before = sounds.played.size()
	for t in 70:  # in real time, like a game
		sim.step_ticks(1)
		await create_timer(SimScript.TICK_TIME).timeout
	await create_timer(0.6).timeout
	check("a fight on screen: attack sounds (%d)" % count(sounds.played, before, "attack"), count(sounds.played, before, "attack") >= 2)
	check("...cries when hit (%d)" % count(sounds.played, before, "defend"), count(sounds.played, before, "defend") >= 1)
	check("...and a death (%d, %s)" % [count(sounds.played, before, "death"), str(sounds.played.slice(before))], count(sounds.played, before, "death") == 1 and sim.get_unit(b).is_empty())

	# Far off screen: quiet.
	sim.clear_units()
	var far := Vector2(cam.target.x, cam.target.z) + Vector2(300, 300)
	var c: int = sim.add_unit(0, 0, far + Vector2(-3.4, 0))
	var d: int = sim.add_unit(1, 2, far + Vector2(3.4, 0))
	await frames(2)
	check("(that fight is off screen)", not game._on_screen(view.world_position(c)))
	before = sounds.played.size()
	for t in 60:
		sim.step_ticks(1)
		await process_frame
	await create_timer(0.5).timeout
	check("a fight off screen makes no sound", count(sounds.played, before, "attack") == 0
			and count(sounds.played, before, "defend") == 0)

	# Building sounds: laid down (thud and knocks), finished (sparkle).
	sim.clear_units()
	sim.resources[0] = [999, 999, 999]
	var home: Dictionary = sim.hq_of(0)
	var spot := Vector2.ZERO
	for ring in [30.0, 36.0]:
		for k in 16:
			var p: Vector2 = Vector2(home.x, home.z) / 100.0 + Vector2.from_angle(k * TAU / 16) * ring
			if spot == Vector2.ZERO and sim.can_place("quarry", p, 0):
				spot = p
	cam.target = Vector3(spot.x, 0, spot.y)
	cam.refit()
	await frames(2)
	before = sounds.played.size()
	sim.command_build(0, "quarry", spot)
	sim.step_ticks(3)
	check("laying down a building plays its construction sound", count(sounds.played, before, "build_place") == 1)
	sim.step_ticks(SimScript.BUILDINGS.quarry.build + 2)
	await frames(2)
	check("...and finishing it plays another", count(sounds.played, before, "build_done") == 1)

	# Settings: music and effects volumes go to their own buses, and stick.
	var Settings = load("res://scripts/settings.gd")
	Settings.set_volume("music", 0.25)
	Settings.set_volume("sfx", 0.0)
	var music_bus: int = AudioServer.get_bus_index("Music")
	var sfx_bus: int = AudioServer.get_bus_index("SFX")
	check("the music volume setting turns the music down", music_bus >= 0
			and AudioServer.get_bus_volume_db(music_bus) < -20 and not AudioServer.is_bus_mute(music_bus))
	check("effects at 0 are silent", sfx_bus >= 0 and AudioServer.is_bus_mute(sfx_bus))
	check("...and the settings are remembered", is_equal_approx(Settings.get_volume("music"), 0.25)
			and is_equal_approx(Settings.get_volume("sfx"), 0.0))
	check("the Music and SFX buses come from the bus layout (there from the start, sent to Master)",
			music_bus == 1 and sfx_bus == 2 and AudioServer.get_bus_send(1) == &"Master"
			and AudioServer.get_bus_send(2) == &"Master" and AudioServer.bus_count == 3)
	check("voices play on the effects bus", sounds._voices[0].bus == &"SFX")
	var panel: Control = Settings.new()
	root.add_child(panel)
	await frames(1)
	panel._music_slider.value = 80
	check("the Settings window's music slider applies right away", is_equal_approx(Settings.get_volume("music"), 0.8))
	panel.close()
	Settings.set_volume("music", Settings.DEFAULTS.music)
	Settings.set_volume("sfx", Settings.DEFAULTS.sfx)
	check("there's a gear button in game, at the top right", game.hud.settings_button.visible
			and game.hud.settings_button.anchor_left == 1.0)

	# Music: the start screen's track, then the battle track in a game.
	game._show_start_menu()
	await frames(1)
	check("the start screen plays Majestic Crescendo", game.music.current == "menu" and game.music._players[game.music._active].playing)
	var menu: Control = root.get_node("Main/HUD").get_children().filter(func(c): return c.has_signal("vs_computer")).front()
	menu.vs_computer.emit()
	await frames(1)
	check("a game plays Antes de la Batalla (crossfading)", game.music.current == "battle"
			and game.music._players[game.music._active].stream.loop)
	check("...on the music bus", game.music._players[0].bus == &"Music")

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
