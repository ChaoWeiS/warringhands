extends SceneTree
## Easy to read: health bars go green / yellow / red, health bars and
## numbers grow when zoomed out, the teams are a strong red and blue, and
## the Group button and selection sit at the bottom left.
## Run: godot --headless -s res://tests/test_readability.gd

const UI := preload("res://scripts/ui_style.gd")

var failures := 0


func _initialize() -> void:
	root.size = Vector2i(1920, 1080)
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
	var bview: Node3D = root.get_node("Main/World/Buildings")
	var uview: Node3D = root.get_node("Main/World/Units")
	sim.set_process(false)

	check("health: green when healthy", UI.health_color(1.0) == UI.HEALTH_GREEN and UI.health_color(0.41) == UI.HEALTH_GREEN)
	check("...yellow from 40%", UI.health_color(0.4) == UI.HEALTH_YELLOW and UI.health_color(0.21) == UI.HEALTH_YELLOW)
	check("...red from 20%", UI.health_color(0.2) == UI.HEALTH_RED and UI.health_color(0.05) == UI.HEALTH_RED)

	var hq: Dictionary = sim.hq_of(0)
	hq.hp = roundi(hq.max_hp * 0.35)
	var u: Dictionary = sim.units.filter(func(x): return x.team == 0).front()
	u.hp = 15
	await frames(2)
	var hq_bar: Sprite3D = bview._views[hq.id].hp_fill
	check("a building at 35% shows a yellow bar", hq_bar.visible and hq_bar.modulate == UI.HEALTH_YELLOW)
	check("a hand at 15% shows a red bar", uview._views[u.id].hp_fill.modulate == UI.HEALTH_RED)

	var cam: Camera3D = panes._leaves()[0].camera
	cam.units_per_pixel = game.HOME_ZOOM
	await frames(2)
	var near: float = hq_bar.scale.x
	cam.units_per_pixel = game.HOME_ZOOM * 3.0
	await frames(2)
	check("zoomed out 3x, building health bars draw 3x bigger (%.1f -> %.1f)" % [near, hq_bar.scale.x],
			is_equal_approx(near, 1.0) and is_equal_approx(hq_bar.scale.x, 3.0))
	check("...and numbers too", is_equal_approx(bview.zoom_scale, 3.0) and is_equal_approx(uview.zoom_scale, 3.0))

	var red: Color = uview.TEAM_COLORS[0]
	var blue: Color = uview.TEAM_COLORS[1]
	check("the teams are a strong red and blue (not pastel)", red.s > 0.6 and blue.s > 0.6 and red.v < 0.95 and blue.v < 0.95)

	game._select(sim.units.filter(func(x): return x.team == 0).map(func(x): return x.id))
	await frames(3)
	var screen: Vector2 = root.get_visible_rect().size
	var group: Rect2 = game.hud.group_button.get_global_rect()
	var chips: Rect2 = game.bar.get_global_rect()
	var orders: Rect2 = game.bar.actions.get_global_rect()
	var build: Rect2 = game.hud._build_toggle.get_global_rect()
	var tab: Rect2 = panes._tabs(panes._leaves()[0]).filter(func(t): return t[0] == panes.Side.LEFT)[0][2]
	check("Build sits on the left above the screen-cutting tab", build.position.x < 60 and build.end.y <= tab.position.y + 4)
	check("Attack / Hold / Queue stack on the left below the tab", orders.position.x < 60 and orders.position.y >= tab.end.y - 4
			and orders.size.y > orders.size.x * 2.0)
	check("...with Group just under them", group.position.x < 60 and group.position.y >= orders.end.y and group.end.y <= screen.y)
	check("the selected hands are a row along the bottom, beside the column",
			chips.position.x >= group.end.x and chips.end.y > screen.y - 60 and chips.size.x > chips.size.y * 2.0)
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
