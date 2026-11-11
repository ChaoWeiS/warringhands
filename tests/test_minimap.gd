extends SceneTree
## Minimaps: one in the top-left of every pane, showing where that pane looks;
## touching one moves that pane's camera; Settings turns them off and on.
## Run: godot --headless -s res://tests/test_minimap.gd

const Settings := preload("res://scripts/settings.gd")

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
	Settings.set_option("minimap", true)
	await frames(3)
	var game: Node = root.get_node("Main/Game")
	var panes: Control = root.get_node("Main/Panes")
	var mm: Control = game.minimap
	var leaf = panes._leaves()[0]
	var map: Control = mm.map_of(leaf)
	check("there's a minimap in the pane's top-left corner", map != null and map.visible
			and map.global_position.distance_to(leaf.rect.position + Vector2(12, 12)) < 1.0 and map.size.x >= 100)

	# Touch the minimap's bottom-right quarter: the pane looks there.
	var before: Vector3 = leaf.camera.target
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = map.size * 0.75
	map.gui_input.emit(touch)
	var area: Rect2 = leaf.camera.map_rect
	var want: Vector2 = area.position + area.size * 0.75
	check("touching the minimap moves that pane's camera there", Vector2(leaf.camera.target.x, leaf.camera.target.z).distance_to(want) < 1.0
			and leaf.camera.target != before)
	check("...and the minimap blocks the touch from the pane underneath", panes._blocked(map.global_position + map.size * 0.5))

	# Split the screen: every pane gets its own.
	panes._split_leaf(leaf, true, 0.5)
	await frames(2)
	var leaves: Array = panes._leaves()
	var all_have := true
	for l in leaves:
		var m: Control = mm.map_of(l)
		all_have = all_have and m != null and m.visible and m.global_position.distance_to(l.rect.position + Vector2(12, 12)) < 1.0
	check("after a split, each of the %d panes has its own minimap" % leaves.size(), leaves.size() == 2 and all_have)

	# Settings: off hides them, on brings them back.
	var panel: Control = Settings.new()
	root.add_child(panel)
	await frames(1)
	panel._minimap_toggle.button_pressed = false
	await frames(2)
	check("turning Minimap off in Settings hides them", mm.get_child_count() == 0 or mm.get_children().all(func(c): return c.is_queued_for_deletion()))
	check("...and it's remembered", not Settings.get_option("minimap"))
	panel._minimap_toggle.button_pressed = true
	await frames(2)
	check("turning it back on shows them again", mm.map_of(panes._leaves()[0]) != null)
	panel.close()

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
