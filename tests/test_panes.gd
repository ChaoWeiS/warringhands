extends SceneTree
## Drives the pane layout with fake touches and checks the results.

var panes: Control
var out_dir: String
var failures := 0


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


func drag(index: int, from: Vector2, to: Vector2, steps: int = 8) -> void:
	for i in range(1, steps + 1):
		var e := InputEventScreenDrag.new()
		e.index = index
		e.position = from.lerp(to, float(i) / steps)
		e.relative = (to - from) / steps
		root.push_input(e, true)


func swipe(from: Vector2, to: Vector2) -> void:
	touch(0, from, true)
	drag(0, from, to)
	touch(0, to, false)


## Centre of a pane's cut tab touch area. side: 0 left, 1 right, 2 top, 3 bottom.
func tab_pt(leaf, side: int) -> Vector2:
	return panes._tabs(leaf)[side][2].get_center()


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func shot(name: String) -> void:
	for i in 4:
		await process_frame
	if out_dir != "":
		root.get_texture().get_image().save_png(out_dir + "/" + name + ".png")


func _run() -> void:
	for i in 5:
		await process_frame
	panes = root.get_node("Main/Panes")
	var size: Vector2 = panes.size
	print("screen ", size)
	check("starts with 1 pane", panes.pane_count() == 1)
	await shot("1_single")

	# Short swipe from the left tab: should NOT cut.
	swipe(tab_pt(panes._leaves()[0], 0), Vector2(300, size.y / 2))
	check("short swipe does not cut", panes.pane_count() == 1)

	# Full swipe from the left tab across: horizontal cut (top / bottom).
	swipe(tab_pt(panes._leaves()[0], 0), Vector2(size.x - 200, 640))
	check("left-tab swipe cuts into 2", panes.pane_count() == 2)
	var leaves: Array = panes._leaves()
	check("cut is stacked (top/bottom)", leaves[0].rect.position.y < leaves[1].rect.position.y)

	# Cut the bottom pane from its top tab, downwards: side-by-side.
	var bottom: Rect2 = leaves[1].rect
	var tab_point := tab_pt(leaves[1], 2)
	swipe(tab_point, Vector2(1240, bottom.end.y - 40))
	check("top-tab swipe cuts bottom pane into 2 (3 total)", panes.pane_count() == 3)

	# Two-finger pinch out in the top pane zooms only that pane.
	leaves = panes._leaves()
	var top_cam: Camera3D = leaves[0].camera
	var other_cam: Camera3D = leaves[1].camera
	var top_before: float = top_cam.units_per_pixel
	var other_before: float = other_cam.units_per_pixel
	var c: Vector2 = leaves[0].rect.get_center()
	touch(1, c - Vector2(100, 0), true)
	touch(2, c + Vector2(100, 0), true)
	for i in range(1, 9):
		var e1 := InputEventScreenDrag.new()
		e1.index = 1
		e1.position = c - Vector2(100 + i * 30, 0)
		root.push_input(e1, true)
		var e2 := InputEventScreenDrag.new()
		e2.index = 2
		e2.position = c + Vector2(100 + i * 30, 0)
		root.push_input(e2, true)
	touch(1, c - Vector2(340, 0), false)
	touch(2, c + Vector2(340, 0), false)
	check("pinch zooms in the top pane", top_cam.units_per_pixel < top_before * 0.6)
	check("other panes unaffected", is_equal_approx(other_cam.units_per_pixel, other_before))

	# Two-finger pan in the bottom-left pane moves its camera.
	var bl: Dictionary = {}
	var bl_cam: Camera3D = leaves[1].camera
	var t_before: Vector3 = bl_cam.target
	var bc: Vector2 = leaves[1].rect.get_center()
	touch(3, bc + Vector2(-60, 0), true)
	touch(4, bc + Vector2(60, 0), true)
	for i in range(1, 9):
		var e3 := InputEventScreenDrag.new()
		e3.index = 3
		e3.position = bc + Vector2(-60 + i * 20, 0)
		root.push_input(e3, true)
		var e4 := InputEventScreenDrag.new()
		e4.index = 4
		e4.position = bc + Vector2(60 + i * 20, 0)
		root.push_input(e4, true)
	touch(3, bc + Vector2(100, 0), false)
	touch(4, bc + Vector2(220, 0), false)
	check("two-finger pan moves the pane's camera", bl_cam.target.distance_to(t_before) > 5.0)

	await shot("2_three_panes")

	# Grabbing a divider right at its middle, or up to 36 px off it, must
	# move the divider, never start a cut.
	var hsplit = panes._splits()[0]
	var hline: Array = panes._divider_line(hsplit)
	var hmid: Vector2 = (hline[0] + hline[1]) * 0.5
	for off in [0.0, 20.0, -20.0, 36.0, -36.0]:
		touch(5, hmid + Vector2(0, off), true)
		var mode = panes._fingers[5].mode if panes._fingers.has(5) else -1
		touch(5, hmid + Vector2(0, off), false)
		check("touch %+d px from divider middle grabs the divider" % int(off), mode == panes.Mode.DIVIDER)
	check("probing the divider changed nothing", panes.pane_count() == 3)

	# A finger lands on a cut tab by accident, then a second finger comes
	# down to zoom: no cut, and the pane zooms.
	var tl = panes._leaves()[0]
	var tz: float = tl.camera.units_per_pixel
	var tp: Vector2 = tab_pt(tl, 0)
	touch(6, tp, true)
	touch(7, tp + Vector2(400, 0), true)
	for i in range(1, 9):
		var a := InputEventScreenDrag.new()
		a.index = 6
		a.position = tp + Vector2(-i * 4, 0)
		root.push_input(a, true)
		var b2 := InputEventScreenDrag.new()
		b2.index = 7
		b2.position = tp + Vector2(400 + i * 40, 0)
		root.push_input(b2, true)
	touch(6, tp + Vector2(-32, 0), false)
	touch(7, tp + Vector2(720, 0), false)
	check("second finger turns an accidental cut into a zoom (no cut)", panes.pane_count() == 3)
	check("...and the pane zoomed", tl.camera.units_per_pixel < tz)

	# Drag the vertical divider in the bottom row a little: resize, no merge.
	var split = panes._splits()[1]
	var line: Array = panes._divider_line(split)
	var mid: Vector2 = (line[0] + line[1]) * 0.5 + Vector2(0, 60)
	touch(0, mid, true)
	drag(0, mid, mid + Vector2(-200, 0))
	await shot("3_resizing")
	touch(0, mid + Vector2(-200, 0), false)
	check("resize keeps 3 panes", panes.pane_count() == 3)

	# Drag it nearly to the right edge: the right pane closes (merge).
	line = panes._divider_line(split)
	mid = (line[0] + line[1]) * 0.5 + Vector2(0, 60)
	touch(0, mid, true)
	drag(0, mid, Vector2(size.x - 30, mid.y))
	touch(0, Vector2(size.x - 30, mid.y), false)
	check("dragging divider to the edge merges (2 panes)", panes.pane_count() == 2)

	# Drag the horizontal divider to the top: back to one pane.
	split = panes._splits()[0]
	line = panes._divider_line(split)
	mid = (line[0] + line[1]) * 0.5 + Vector2(300, 0)
	touch(0, mid, true)
	drag(0, mid, Vector2(mid.x, 20))
	touch(0, Vector2(mid.x, 20), false)
	check("dragging divider to the top merges (1 pane)", panes.pane_count() == 1)

	# A side-by-side cut from the bottom tab, then a 2x2 grid for a screenshot.
	swipe(tab_pt(panes._leaves()[0], 3), Vector2(size.x * 0.5, 200))
	leaves = panes._leaves()
	for leaf in leaves:
		var r: Rect2 = leaf.rect
		swipe(tab_pt(leaf, 0), Vector2(r.end.x - 20, r.get_center().y))
	check("grid of 4 panes", panes.pane_count() == 4)
	# Give each pane a different view.
	leaves = panes._leaves()
	leaves[1].camera.zoom_at(4.0, leaves[1].rect.size * 0.5)
	leaves[2].camera.pan_by_screen(Vector2(250, 120))
	leaves[2].camera.zoom_at(2.5, leaves[2].rect.size * 0.5)
	leaves[3].camera.pan_by_screen(Vector2(-200, -160))
	leaves[3].camera.zoom_at(6.0, leaves[3].rect.size * 0.5)
	await shot("4_grid")

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
