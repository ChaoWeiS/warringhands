extends SceneTree
## Every map is playable: both HQs on open ground with room to build, the
## armies start on land, the HQs can reach each other on foot, and every
## resource spot can be reached from home. (Mirrored: fair by construction.)
## Run: godot --headless -s res://tests/test_maps.gd

const Field := preload("res://scripts/field.gd")
const SimScript := preload("res://scripts/sim/sim.gd")
const Maps := preload("res://scripts/maps.gd")

var failures := 0


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func(): print("FAIL timed out"); quit(1))
	_run()


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func _run() -> void:
	await process_frame
	var dump := {}
	check("there are at least 3 maps", Maps.ORDER.size() >= 3)
	for id in Maps.ORDER:
		var field: Node3D = Field.new()
		field.map_id = id
		field.build()
		var sim: Node = SimScript.new()
		sim.field = field
		sim._spawn_armies()
		sim._spawn_bases()
		var name: String = Maps.MAPS[id].name
		var grid = sim.nav()
		var hqs: Array = [sim.hq_of(0), sim.hq_of(1)]
		# HQs: on open ground.
		var hq_ok := true
		for hq in hqs:
			var c := Vector2(hq.x, hq.z) / 100.0
			for k in 12:
				hq_ok = hq_ok and field.is_walkable(c + Vector2.from_angle(k * TAU / 12) * 10.0)
		check("%s: both HQs stand on open ground" % name, hq_ok)
		# Armies: on land, not in anything.
		var army_ok := true
		for u in sim.units:
			army_ok = army_ok and grid.is_walkable_cell(grid.cell_of(u.x, u.z))
		check("%s: every hand starts on open ground (%d)" % [name, sim.units.size()], army_ok and sim.units.size() > 0)
		# The two HQs can reach each other.
		var a: Dictionary = hqs[0]
		var b: Dictionary = hqs[1]
		var route: Array = grid.find_route(a.x + 1500, a.z, b.x - 1500, b.z)
		check("%s: there's a way on foot from one HQ to the other" % name, not route.is_empty())
		# Every resource spot reachable from the nearest HQ.
		var unreachable: Array = []
		for n in sim.nodes:
			if n.tree:
				continue
			var home: Dictionary = a if sim._dist2(n, a) <= sim._dist2(n, b) else b
			var near: Vector2i = grid.nearest_walkable(grid.cell_of(n.x, n.z))
			var centre: Vector2i = grid.cell_centre(near)
			var path: Array = grid.find_route(home.x + (1500 if home == a else -1500), home.z, centre.x, centre.y)
			if path.is_empty() or Vector2(centre).distance_to(Vector2(n.x, n.z)) > n.radius + 1200:
				unreachable.append(n.res)
		check("%s: every resource spot can be reached (%d spots)" % [name, sim.nodes.filter(func(n): return not n.tree).size()],
				unreachable.is_empty())
		# Each side has every resource.
		var has_all := true
		for res in 3:
			has_all = has_all and sim.nodes.any(func(n): return n.res == res)
		check("%s: stone, wood and metal all on the map" % name, has_all)
		# Room for a factory near each HQ.
		var room := true
		for team in 2:
			var hq: Dictionary = hqs[team]
			var found := false
			for ring in [26.0, 36.0, 46.0]:
				for k in 16:
					var p: Vector2 = Vector2(hq.x, hq.z) / 100.0 + Vector2.from_angle(k * TAU / 16) * ring
					found = found or sim.can_place("quarry", p, team)
			room = room and found
		check("%s: room to build next to each HQ" % name, room)
		# Plateaus: walkable on top, reached by ramps, cliff edge blocked.
		var tops_ok := true
		var cliff_ok := true
		var ramps_ok: bool = field.ramps.size() >= 1 and field.climbable.size() >= 1
		for i in field.plateaus.size():
			if not field.climbable.has(i):
				# Scenery: no way up.
				var mid: Vector2 = field._poly_center(field.plateaus[i])
				ramps_ok = ramps_ok and not field.is_walkable(mid)
				continue
			var poly: PackedVector2Array = field.plateaus[i]
			var c: Vector2 = field._poly_center(poly)
			var top_cell: Vector2i = grid.cell_of(roundi(c.x * 100), roundi(c.y * 100))
			var home: Dictionary = a if Vector2(a.x, a.z).distance_to(c * 100) <= Vector2(b.x, b.z).distance_to(c * 100) else b
			var up: Array = grid.find_route(home.x + (1500 if home == a else -1500), home.z, top_cell.x * 0 + roundi(c.x * 100), roundi(c.y * 100))
			tops_ok = tops_ok and field.is_walkable(c) and not up.is_empty() and is_equal_approx(field.height_at(c), field.PLATEAU_HEIGHT)
			# Halfway round the cliff from each ramp: blocked.
			for k in 16:
				var dir: Vector2 = Vector2.from_angle(k * TAU / 16)
				var edge: Vector2 = field._edge_point(poly, dir)
				if field.ramp_at(edge) < 0 and field.ramp_at(edge + dir * 2.0) < 0:
					cliff_ok = cliff_ok and not field.is_walkable(edge)
		check("%s: the plateaus with ramps (%d of %d) can be walked up to" % [name, field.climbable.size(), field.plateaus.size()], tops_ok)
		check("%s: ...only by their ramps (%d); other cliffs and plateaus are blocked" % [name, field.ramps.size()], ramps_ok and cliff_ok)
		var no_build := true
		for poly in field.plateaus:
			no_build = no_build and not sim.can_place("quarry", field._poly_center(poly))
		check("%s: nothing can be built up on a plateau" % name, no_build)
		dump[id] = {
			"coast": Array(field.coastline).map(func(p): return [p.x, p.y]),
			"lakes": field.lakes.map(func(poly): return Array(poly).map(func(p): return [p.x, p.y])),
			"plateaus": field.plateaus.map(func(poly): return Array(poly).map(func(p): return [p.x, p.y])),
			"trees": field.forests.reduce(func(acc, f): return acc + f.trees.map(func(t): return [t.x, t.y]), []),
			"nodes": sim.nodes.filter(func(n): return not n.tree).map(func(n): return [n.res, n.x / 100.0, n.z / 100.0]),
			"ramps": field.ramps.map(func(r): return [r.edge.x, r.edge.y, r.dir.x, r.dir.y]),
			"hqs": hqs.map(func(h): return [h.x / 100.0, h.z / 100.0]),
			"units": sim.units.map(func(u): return [u.team, u.x / 100.0, u.z / 100.0]),
		}
		sim.free()
		field.free()
	var path: String = OS.get_environment("MAP_DUMP")
	if path != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(dump))
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)
