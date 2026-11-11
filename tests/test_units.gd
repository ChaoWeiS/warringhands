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


## Smallest distance (sim units) between any two of these units.
func min_gap(ids: Array) -> int:
	var best: int = 1 << 30
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Dictionary = sim.get_unit(ids[i])
			var b: Dictionary = sim.get_unit(ids[j])
			var dx: int = a.x - b.x
			var dz: int = a.z - b.z
			best = mini(best, int(sqrt(float(dx * dx + dz * dz))))
	return best


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
	sim._ais.clear()  # ...and both sides

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

	# Sprites: every unit plays its idle animation; states can be switched.
	var anim_ok := true
	for id in mine + theirs:
		var spr = view._views[id].sprite
		anim_ok = anim_ok and spr.is_playing() and spr.animation == "idle" \
				and spr.sprite_frames.get_frame_count("idle") == 5
	check("all units play a 5-frame idle animation", anim_ok)
	view.set_state(mine[0], "attack")
	view.set_state(mine[4], "defend")
	check("units can switch to attack / defend", view._views[mine[0]].sprite.animation == "attack" \
			and view._views[mine[4]].sprite.animation == "defend")
	await shot("units_1b_states")
	view.set_state(mine[0], "idle")
	view.set_state(mine[4], "idle")

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

	# Walking units play the moving animation (it hops by itself); when they
	# stop they go back to idle.
	var walker_spr: AnimatedSprite3D = view._views[mine[1]].sprite
	sim.command_move([mine[1]], Vector3(sim.unit_ground(mine[1]).x + 15, 0, sim.unit_ground(mine[1]).y))
	sim.step_ticks(4)
	view._update_combat_look()
	check("a walking unit plays its moving animation", walker_spr.animation == "move"
			and walker_spr.sprite_frames.get_frame_count("move") == 5)
	sim.step_ticks(60)  # arrives
	view._update_combat_look()
	check("after arriving it's idle again", walker_spr.animation == "idle")
	game._select([first])

	# Tap the ground: the unit walks there.
	# (Left of the army: clear ground, nobody standing there.)
	var dest_screen: Vector2 = screen_pos(leaf, first) + Vector2(-330, 0)
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
	game._unselect_all()
	check("unselecting clears the bar", game.selection.is_empty() and not bar.visible)
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
	var far := Vector2(410 + 20, 410 + 190)  # open ground, away from both armies
	check("cross-pane destination is open ground", field.is_walkable(far))
	right.camera.target = Vector3(far.x, 0, far.y)
	right.camera.refit()
	await frames(3)
	tap(right.rect.get_center())
	check("selection survives tapping in another pane", game.selection.size() == 12)
	sim.step_ticks(900)
	var mean := Vector2.ZERO
	for id in mine:
		mean += sim.unit_ground(id)
	mean /= mine.size()
	check("army walked to the spot tapped in the other pane (%.1f away)" % mean.distance_to(far), mean.distance_to(far) < 3.0)
	if mean.distance_to(far) >= 3.0:
		for id in mine:
			var uu: Dictionary = sim.get_unit(id)
			print("  unit ", id, " at ", sim.unit_ground(id), " target ", Vector2(uu.tx, uu.tz) / 100.0, " moving ", uu.moving, " path ", uu.path.size())
	var all_stopped := true
	for id in mine:
		all_stopped = all_stopped and not sim.get_unit(id).moving
	check("...and every unit has arrived", all_stopped)
	await shot("units_3_cross_pane")

	# Collision: nobody overlaps once the army has settled.
	check("settled army: no units overlap (closest %.1f apart)" % (min_gap(mine) / 100.0),
			min_gap(mine) >= sim.RADIUS * 2 * 0.9)

	# Collision while walking: rocks and scissors swap sides straight through
	# each other's rows (and the papers between them). Bodies may squeeze a
	# little but never pass through each other or onto blocked ground.
	var rocks: Array = mine.filter(func(id): return sim.get_unit(id).kind == SimScript.Kind.ROCK)
	var scissors: Array = mine.filter(func(id): return sim.get_unit(id).kind == SimScript.Kind.SCISSORS)
	var south := far + Vector2(0, 25)
	var north := far + Vector2(0, -25)
	check("crossing targets are open ground", field.is_walkable(south) and field.is_walkable(north))
	sim.command_move(rocks, Vector3(south.x, 0, south.y))
	sim.command_move(scissors, Vector3(north.x, 0, north.y))
	var tightest: int = 1 << 30
	var on_open_ground := true
	var nav_grid = sim.nav()
	for i in 500:
		sim.step_ticks(1)
		tightest = mini(tightest, min_gap(mine))
		for id in mine:
			var cu: Dictionary = sim.get_unit(id)
			on_open_ground = on_open_ground and nav_grid.is_walkable_cell(nav_grid.cell_of(cu.x, cu.z))
	check("crossing groups never overlap much (closest %.1f apart, bodies %.1f)" % [tightest / 100.0, sim.RADIUS * 2 / 100.0],
			tightest >= sim.RADIUS * 2 * 0.9)
	check("nobody was pushed onto blocked ground", on_open_ground)
	var crossed := true
	for id in rocks:
		crossed = crossed and sim.unit_ground(id).y > far.y + 10
	for id in scissors:
		crossed = crossed and sim.unit_ground(id).y < far.y - 10
	check("rocks and scissors made it past each other", crossed)
	var settled := true
	for id in mine:
		settled = settled and not sim.get_unit(id).moving
	check("everyone settled after crossing", settled)

	# Giving way: a walker heads straight through one of our idle units. The
	# idle one steps aside (sideways), they never overlap much, and the
	# walker gets where it's going.
	var stander: int = scissors[0]
	var mover: int = rocks[0]
	var q := Vector2.ZERO
	for cand in [far + Vector2(0, 45), far + Vector2(0, -45), far + Vector2(-50, 0), far + Vector2(50, 0)]:
		var clear := true
		for k in 13:
			clear = clear and field.is_walkable(cand + Vector2(-30 + k * 5, 0))
		if clear:
			q = cand
			break
	check("found clear ground for the give-way test", q != Vector2.ZERO)
	sim.command_move([stander], Vector3(q.x, 0, q.y))
	sim.command_move([mover], Vector3(q.x - 30, 0, q.y))
	sim.step_ticks(700)
	var stand_before: Vector2 = sim.unit_ground(stander)
	sim.command_move([mover], Vector3(q.x + 30, 0, q.y))
	var closest: int = 1 << 30
	for i in 300:
		sim.step_ticks(1)
		closest = mini(closest, min_gap([stander, mover]))
	var moved: Vector2 = sim.unit_ground(stander) - stand_before
	check("walker reached the far side (%.1f away)" % sim.unit_ground(mover).distance_to(Vector2(q.x + 30, q.y)),
			sim.unit_ground(mover).distance_to(Vector2(q.x + 30, q.y)) < 1.0)
	check("they never overlapped (closest %.1f, bodies %.1f)" % [closest / 100.0, sim.RADIUS * 2 / 100.0],
			closest >= sim.RADIUS * 2 * 0.9)
	check("the idle unit stepped aside sideways (moved %.1f across, %.1f along)" % [absf(moved.y), absf(moved.x)],
			absf(moved.y) > 2.0 and absf(moved.y) > absf(moved.x))

	# Fanning out: two groups ordered onto the same spot clump up, then
	# drift apart until each unit has its own space.
	var papers: Array = mine.filter(func(id): return sim.get_unit(id).kind == SimScript.Kind.PAPER)
	var clump: Array = rocks + papers
	sim.command_move(rocks, Vector3(far.x, 0, far.y))
	sim.command_move(papers, Vector3(far.x, 0, far.y))
	sim.step_ticks(500)
	check("clumped units fanned out to their own space (closest %.1f, comfort %.1f)" % [min_gap(clump) / 100.0, sim.COMFORT / 100.0],
			min_gap(clump) >= sim.COMFORT * 0.85)

	# Pathfinding: walk around the central lake. The straight line between
	# the two points crosses the lake; the unit must go around it, never
	# stepping onto blocked ground, and arrive.
	var nav = sim.nav()
	var walker: int = mine[2]
	var west := Vector2(410 - 80, 410)
	var east := Vector2(410 + 75, 410 + 20)
	check("lake test points are open ground", field.is_walkable(west) and field.is_walkable(east))
	check("the straight line between them crosses the lake", not field.is_walkable(Vector2(410, 410)))
	sim.command_move([walker], Vector3(west.x, 0, west.y))
	sim.step_ticks(1200)
	check("walker reached the west side of the lake", sim.unit_ground(walker).distance_to(west) < 1.0)
	sim.command_move([walker], Vector3(east.x, 0, east.y))
	sim.step_ticks(sim.COMMAND_DELAY + 1)  # orders take effect after the delay
	var waypoints: int = sim.get_unit(walker).path.size()
	check("route around the lake has turns (%d waypoints)" % waypoints, waypoints >= 2)
	var stayed_clear := true
	for i in 600:
		sim.step_ticks(1)
		var w: Dictionary = sim.get_unit(walker)
		stayed_clear = stayed_clear and nav.is_walkable_cell(nav.cell_of(w.x, w.z))
	check("walker never stepped on water or other blocked ground", stayed_clear)
	check("walker reached the far side of the lake (%.1f away)" % sim.unit_ground(walker).distance_to(east),
			sim.unit_ground(walker).distance_to(east) < 1.0)

	# An order into the middle of a lake: go to the nearest shore and stop.
	sim.command_move([walker], Vector3(410, 0, 410))
	sim.step_ticks(600)
	var at: Vector2 = sim.unit_ground(walker)
	check("ordered into the lake: stops at the shore (%.1f from centre)" % at.distance_to(Vector2(410, 410)),
			not sim.get_unit(walker).moving and nav.is_walkable_cell(nav.cell_of(sim.get_unit(walker).x, sim.get_unit(walker).z))
			and at.distance_to(Vector2(410, 410)) < 70.0)

	# Ordering a unit into the sea: it stops at the shore.
	sim.command_move([first], Vector3(20, 0, 20))
	sim.step_ticks(1500)
	var u: Dictionary = sim.get_unit(first)
	check("unit sent to sea stops on land", field.is_on_land(sim.unit_ground(first)) and not u.moving)

	# Enemies hold their ground: walking into the enemy army doesn't push
	# through it. Our unit is blocked, never overlaps them, and stops.
	# (Combat off here, to test pure collision; fighting has its own tests.)
	sim.combat_enabled = false
	var theirs_before: Dictionary = {}
	for id in theirs:
		theirs_before[id] = sim.unit_ground(id)
	var enemy_centre := Vector2.ZERO
	for id in theirs:
		enemy_centre += sim.unit_ground(id)
	enemy_centre /= theirs.size()
	var intruder: int = mine[5]
	sim.command_move([intruder], Vector3(enemy_centre.x, 0, enemy_centre.y))
	var nearest_enemy: int = 1 << 30
	for i in 2500:
		sim.step_ticks(1)
		for id in theirs:
			nearest_enemy = mini(nearest_enemy, min_gap([intruder, id]))
		if not sim.get_unit(intruder).moving and i > 50:
			break
	var enemy_shift := 0.0
	for id in theirs:
		enemy_shift = maxf(enemy_shift, sim.unit_ground(id).distance_to(theirs_before[id]))
	check("can't walk through enemies (closest %.1f, bodies %.1f)" % [nearest_enemy / 100.0, sim.RADIUS * 2 / 100.0],
			nearest_enemy >= sim.RADIUS * 2 * 0.9)
	check("enemies held their ground (moved at most %.2f)" % enemy_shift, enemy_shift < 0.5)
	check("blocked unit stopped at the enemy line", not sim.get_unit(intruder).moving
			and sim.unit_ground(intruder).distance_to(enemy_centre) < 40.0)
	sim.combat_enabled = true

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
