extends SceneTree
## Checks that cutting / resizing / merging leaves the map still on screen.

var panes: Control
var failures := 0
var out_dir: String


func _initialize() -> void:
	# Same 1920x1200 game screen everywhere (headless runs use a tiny window).
	root.size = Vector2i(1920, 1200)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	# Never hang CI: give up after 60 s.
	create_timer(60.0).timeout.connect(func(): print("FAIL timed out"); quit(1))
	out_dir = OS.get_environment("OUT")
	root.add_child(load("res://scenes/main.tscn").instantiate())
	_run()


func touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	root.push_input(e, true)


func drag_to(index: int, from: Vector2, to: Vector2) -> void:
	for i in range(1, 9):
		var e := InputEventScreenDrag.new()
		e.index = index
		e.position = from.lerp(to, i / 8.0)
		root.push_input(e, true)


func swipe(from: Vector2, to: Vector2) -> void:
	touch(0, from, true)
	drag_to(0, from, to)
	touch(0, to, false)


## Ground point under a screen point, using whichever pane is there.
func ground_under(p: Vector2) -> Vector3:
	var leaf = panes._leaf_at(p)
	return leaf.camera._ground_at(p - leaf.rect.position)


func frames(n: int) -> void:
	for i in n:
		await process_frame


## Centre of a pane's cut tab touch area. side: 0 left, 1 right, 2 top, 3 bottom.
func tab_pt(leaf, side: int) -> Vector2:
	return panes._tabs(leaf)[side][2].get_center()


func check_still(label: String, points: Array, before: Array, tolerance: float) -> void:
	var worst := 0.0
	for i in points.size():
		worst = maxf(worst, ground_under(points[i]).distance_to(before[i]))
	var ok := worst <= tolerance
	print(("PASS " if ok else "FAIL ") + label + "  (max drift %.2f map units)" % worst)
	if not ok:
		failures += 1


func shot(name: String) -> void:
	await frames(4)
	if out_dir != "":
		root.get_texture().get_image().save_png(out_dir + "/" + name + ".png")


func _run() -> void:
	await frames(5)
	panes = root.get_node("Main/Panes")
	# Zoom in a bit first so the test isn't just "whole island".
	var cam = panes._leaves()[0].camera
	cam.zoom_at(2.0, Vector2(900, 650))
	await frames(3)
	var points := [Vector2(400, 250), Vector2(1500, 300), Vector2(500, 950), Vector2(1400, 1000), Vector2(960, 900)]
	var before: Array = points.map(ground_under)
	await shot("still_0_before")

	# Horizontal cut through the middle.
	swipe(tab_pt(panes._leaves()[0], 0), Vector2(1700, 600))
	await frames(3)
	print("panes after cut: ", panes.pane_count())
	check_still("horizontal cut keeps the map still", points, before, 3.0)
	await shot("still_1_cut")

	# Vertical cut of the bottom pane.
	var bottom: Rect2 = panes._leaves()[1].rect
	swipe(tab_pt(panes._leaves()[1], 2), Vector2(bottom.get_center().x, bottom.end.y - 30))
	await frames(3)
	var check_pts := [Vector2(400, 250), Vector2(1500, 300), Vector2(500, 950), Vector2(1400, 1000)]
	var check_before := [before[0], before[1], before[2], before[3]]
	check_still("second cut keeps the map still", check_pts, check_before, 3.0)

	# Resize: drag the horizontal divider down by 200 px. Points in the top
	# pane (which grows) and far below the divider should not move.
	var split = panes._splits()[0]
	var line: Array = panes._divider_line(split)
	var grab: Vector2 = Vector2(300, line[0].y)
	touch(0, grab, true)
	drag_to(0, grab, grab + Vector2(0, 200))
	touch(0, grab + Vector2(0, 200), false)
	await frames(3)
	print("panes after resize: ", panes.pane_count())
	check_still("resize keeps the map still (top pane)", [Vector2(400, 250), Vector2(1500, 300)], [before[0], before[1]], 3.0)

	# Zoom must never change from moving panels.
	var zooms: Array = panes._leaves().map(func(l): return l.camera.units_per_pixel)
	var start_zoom: float = cam.units_per_pixel
	var same := true
	for z in zooms:
		same = same and is_equal_approx(z, start_zoom)
	print(("PASS " if same else "FAIL ") + "all panes keep the original zoom after cuts and resize")
	if not same:
		failures += 1

	# Merge: drag the divider to the bottom. Mid-drag, the shrinking bottom
	# panes must keep their zoom and their map still. After release, the top
	# pane grows to full screen and still shows the same ground.
	var low_pt := Vector2(1400, 1170)
	var low_before: Vector3 = ground_under(low_pt)
	line = panes._divider_line(split)
	grab = Vector2(300, line[0].y)
	touch(0, grab, true)
	drag_to(0, grab, Vector2(300, 1120))
	await frames(3)
	check_still("mid-merge: shrinking pane's map stays still", [low_pt], [low_before], 0.01)
	var mid_zoom_ok := true
	for l in panes._leaves():
		mid_zoom_ok = mid_zoom_ok and is_equal_approx(l.camera.units_per_pixel, start_zoom)
	print(("PASS " if mid_zoom_ok else "FAIL ") + "mid-merge: zoom unchanged")
	if not mid_zoom_ok:
		failures += 1
	drag_to(0, Vector2(300, 1120), Vector2(300, 1190))
	touch(0, Vector2(300, 1190), false)
	await frames(3)
	print("panes after merge: ", panes.pane_count())
	check_still("merge keeps the map still", [Vector2(400, 250), Vector2(1500, 300)], [before[0], before[1]], 3.0)
	print(("PASS " if is_equal_approx(panes._leaves()[0].camera.units_per_pixel, start_zoom) else "FAIL ") + "zoom unchanged after merge")
	await shot("still_2_merged")

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
