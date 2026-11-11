extends SceneTree
## Units: selecting, lassoing, moving, cross-pane orders, the sea, and
## lockstep determinism. Run: godot --headless -s res://tests/test_units.gd

const SimScript := preload("res://scripts/sim/sim.gd")

var panes: Control
var sim: Node
var view: Node3D
var game: Node
var bar: Control
var field: Node3D
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


# --- Helpers -------------------------------------------------------------------

func touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	root.push_input(e, true)


func drag_path(index: int, points: Array) -> void:
	for p in points:
		var e := InputEventScreenDrag.new()
		e.index = index
		e.position = p
		root.push_input(e, true)


func tap(pos: Vector2) -> void:
	touch(0, pos, true)
	touch(0, pos, false)


## A closed loop through `corners`, with points every ~20 px.
func loop_points(corners: Array) -> Array:
	var points: Array = []
	for i in corners.size():
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % corners.size()]
		var steps: int = maxi(1, int(a.distance_to(b) / 20.0))
		for s in steps:
			points.append(a.lerp(b, float(s) / steps))
	return points


func lasso(corners: Array) -> void:
	var points := loop_points(corners)
	touch(0, points[0], true)
	drag_path(0, points.slice(1))
	touch(0, points[points.size() - 1], false)


func screen_pos(leaf, id: int) -> Vector2:
	return leaf.rect.position + leaf.camera.unproject_position(view.world_position(id))


func team_ids(team: int) -> Array:
	var ids: Array = []
	for u in sim.units:
		if u.team == team:
			ids.append(u.id)
	return ids


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await frames(4)
	if out_dir != "":
		root.get_texture().get_image().save_png(out_dir + "/" + name + ".png")


func tab_pt(leaf, side: int) -> Vector2:
	return panes._tabs(leaf)[side][2].get_center()


# --- Tests ---------------------------------------------------------------------

func _run() -> void:
	await frames(5)
	panes = root.get_node("Main/Panes")
	sim = root.get_node("Main/Sim")
	view = root.get_node("Main/World/Units")
	game = root.get_node("Main/Game")
	bar = root.get_node("Main/HUD/SelectionBar")
	field = root.get_node("Main/World/Field")
	sim.set_process(false)  # tests step the sim by hand

	var mine: Array = team_ids(0)
	var theirs: Array = team_ids(1)
	check("each side has 12 units", mine.size() == 12 and theirs.size() == 12)
	var all_on_land := true
	for u in sim.units:
		all_on_land = all_on_land and field.is_on_land(sim.unit_ground(u.id))
	check("everyone starts on land", all_on_land)

	# Zoom the single pane in on our army.
	var leaf = panes._leaves()[0]
	var cam = leaf.camera
	var c := Vector2.ZERO
	for id in mine:
		c += sim.unit_ground(id)
	c /= mine.size()
	cam.target = Vector3(c.x, 0, c.y)
	cam.units_per_pixel = 0.06
	cam.refit()
	await frames(3)
	await shot("units_1_start")

	# Tap a unit: it alone is selected.
	var first: int = mine[0]
	tap(screen_pos(leaf, first))
	check("tapping a unit selects it", game.selection == [first])
	check("selection bar shows", bar.visible)

	# Tapping an enemy doesn't select it.
	tap(screen_pos(leaf, theirs[0]))
	check("enemy units can't be selected (tap became a move order)", game.selection == [first])
	sim.step_ticks(3)
	game._select([first])

	# Tap the ground: the unit walks there.
	var dest_screen: Vector2 = screen_pos(leaf, first) + Vector2(260, 0)
	var dest_ground: Vector3 = cam.ground_at(dest_screen - leaf.rect.position)
	tap(dest_screen)
	check("tapping ground gives a move order", sim.has_pending_commands())
	sim.step_ticks(80)
	var arrived: float = sim.unit_ground(first).distance_to(Vector2(dest_ground.x, dest_ground.z))
	check("unit walked to the tapped spot (%.1f away)" % arrived, arrived < 1.0)
	await frames(2)

	# Lasso all our units.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for id in mine:
		var p := screen_pos(leaf, id)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	lo -= Vector2(50, 50)
	hi += Vector2(50, 50)
	lasso([lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)])
	var got: Array = game.selection.duplicate()
	got.sort()
	check("lasso selects all 12 of our units (got %d)" % got.size(), got == mine)
	await shot("units_2_lassoed")

	# Filter to paper only.
	bar.filter_pressed.emit(SimScript.Kind.PAPER)
	var only_paper: bool = game.selection.size() == 4
	for id in game.selection:
		only_paper = only_paper and sim.get_unit(id).kind == SimScript.Kind.PAPER
	check("filter keeps only the 4 papers", only_paper)

	# Touching the selection bar must not reach the map.
	var before: Array = game.selection.duplicate()
	tap(bar.get_global_rect().get_center())
	check("touching the selection bar doesn't move units", not sim.has_pending_commands())
	check("...or change the selection", game.selection == before)

	# Clear, then start a lasso and put a second finger down: no selection.
	bar.clear_pressed.emit()
	check("clear deselects", game.selection.is_empty() and not bar.visible)
	var pts := loop_points([lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)])
	touch(0, pts[0], true)
	drag_path(0, pts.slice(1, pts.size() / 2))
	touch(1, leaf.rect.get_center() + Vector2(300, 200), true)
	drag_path(0, pts.slice(pts.size() / 2))
	touch(0, pts[pts.size() - 1], false)
	touch(1, leaf.rect.get_center() + Vector2(300, 200), false)
	check("second finger cancels a lasso", game.selection.is_empty())

	# Cross-pane: select everyone in the left pane, tap a spot in the right.
	game._select(mine)
	var r: Rect2 = leaf.rect
	touch(0, tab_pt(leaf, 2), true)
	drag_path(0, [tab_pt(leaf, 2) + Vector2(0, 300), Vector2(r.get_center().x, r.end.y - 40)])
	touch(0, Vector2(r.get_center().x, r.end.y - 40), false)
	check("screen cut into two side-by-side panes", panes.pane_count() == 2)
	var right = panes._leaves()[1]
	var far := Vector2(410 + 60, 410 + 90)  # land, away from both armies
	right.camera.target = Vector3(far.x, 0, far.y)
	right.camera.refit()
	await frames(3)
	tap(right.rect.get_center())
	check("selection survives tapping in another pane", game.selection.size() == 12)
	sim.step_ticks(400)
	var mean := Vector2.ZERO
	for id in mine:
		mean += sim.unit_ground(id)
	mean /= mine.size()
	check("army walked to the spot tapped in the other pane (%.1f away)" % mean.distance_to(far), mean.distance_to(far) < 3.0)
	await shot("units_3_cross_pane")

	# Ordering a unit into the sea: it stops at the shore.
	sim.command_move([first], Vector3(20, 0, 20))
	sim.step_ticks(800)
	var u: Dictionary = sim.get_unit(first)
	check("unit sent to sea stops on land", field.is_on_land(sim.unit_ground(first)) and not u.moving)

	# Lockstep: two simulations given the same orders end up identical.
	var a: Node = SimScript.new()
	var b: Node = SimScript.new()
	for s in [a, b]:
		s.field = field
		root.add_child(s)
		s.set_process(false)
	var start_x: int = a.units[0].x
	for s in [a, b]:
		s.command_move([1, 2, 3, 4, 5, 6], Vector3(380, 0, 470))
		s.step_ticks(37)
		s.command_move([4, 5, 6, 7, 8], Vector3(300.7, 0, 333.3))
		s.command_move([13, 14, 15], Vector3(500, 0, 380))
		s.step_ticks(250)
	var same := true
	for i in a.units.size():
		same = same and a.units[i].x == b.units[i].x and a.units[i].z == b.units[i].z
	check("same orders give identical results (lockstep)", same)
	check("the lockstep sims actually moved units", a.units[0].x != start_x)

	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
