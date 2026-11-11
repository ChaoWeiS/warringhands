extends Node3D
## Battlefield in 2.5D: a pastel 3D island in the sea, with lakes, forests,
## raised plateaus and stone / wood / metal resource spots. Units are drawn
## by units_view.gd.
##
## Every feature is placed twice, mirrored through the island's centre, so
## both players get the same terrain. `is_walkable()` tells the pathfinding
## (scripts/sim/nav_grid.gd) where ground units can go.
##
## Ground positions are 2D (x, z). Game logic will work on that flat plane;
## only the visuals are 3D. The coastline is built from fixed numbers so every
## device builds exactly the same island (needed for lockstep multiplayer).

## Whole world on the ground plane (x, z), sea included.
@export var map_size: Vector2 = Vector2(820, 820)
## Average island radius.
@export var island_radius: float = 330.0
## Points on the coastline (more = smoother).
@export var coast_points: int = 180

# Pastel palette
const SKY := Color("#a9d6eb")
const DEEP_SEA := Color("#8ec5e0")
const SHALLOW_SEA := Color("#b9e3f0")
const SAND := Color("#f6e7c1")
const CLIFF := Color("#e8d3a8")
const GRASS := Color("#c3e6ad")
const GRASS_DARK := Color("#addb96")
const STONE := Color("#cbc5da")
const TRUNK := Color("#d9b48f")
const LEAVES := Color("#f6c3d8")
const METAL := Color("#a9e7e2")
const LAKE := Color("#a6d9ee")
const LAKE_DEEP := Color("#8ec8e3")
const PLATEAU_TOP := Color("#d3ecbf")
const CROWNS := [Color("#b8e0a0"), Color("#a6d68f"), Color("#cfe8b4"), Color("#b8e0a0"), Color("#f6c3d8")]

## Which map (scripts/maps.gd); empty = MatchSetup.map. The layout below
## comes from it: coastline wobble, lakes, forests, plateaus and resource
## spots, as offsets from the island centre, each also placed mirrored
## (turned 180° around the centre) for the other side.
var map_id := ""
var COAST_WAVES: Array = []
var LAKES: Array = []
var FORESTS: Array = []
var PLATEAUS: Array = []
const PLATEAU_HEIGHT := 5.0
## Plateaus with ramps (the map says where) are walkable on top, reached by
## those ramps; the cliff edge (CLIFF_BAND wide) is blocked everywhere else.
## Plateaus without ramps are solid scenery.
const RAMP_LENGTH := 14.0
const RAMP_HALF_WIDTH := 5.5
const CLIFF_BAND := 3.0
# Shape wobble for lakes and plateaus (even frequencies only).
const BLOB_WAVES := [[2, 0.12, 0.4], [4, 0.08, 1.7], [6, 0.05, 3.1]]

## Room kept around obstacles and the shore so units don't clip into them.
const UNIT_CLEARANCE := 3.0
## Trunk size of a forest tree (map units).
const TREE_RADIUS := 3.5
const SHORE_CLEARANCE := 6.0

# Resource spots as offsets from the island centre (already listed for
# both sides in the map, or mirrored here: see _load_map).
var STONES: Array = []
var WOODS: Array = []
var METALS: Array = []
## Team 0's HQ and army start (offsets; team 1's are mirrored).
var hq_offset := Vector2i(-200, -30)
var army_offset := Vector2i(-150, -40)


var coastline: PackedVector2Array = PackedVector2Array()
var lakes: Array = []      # PackedVector2Array outlines
var plateaus: Array = []   # PackedVector2Array outlines
var forests: Array = []    # {center, radius, trees: Array[Vector2]}
## Ramps up the plateaus: {plateau (index), edge: Vector2 (top of the ramp,
## on the cliff), dir: Vector2 (downhill), half_width, length}.
var ramps: Array = []
## Indices (in `plateaus`) of the ones with ramps.
var climbable: Array = []
var _plateau_tops: Array = []   # climbable plateaus shrunk by CLIFF_BAND: walkable
var _plateau_outer: Array = []  # plateaus grown by UNIT_CLEARANCE: cliff + top

# Shapes ground units can't enter, already grown by UNIT_CLEARANCE.
var _blocked_polys: Array = []    # {poly, box}
var _blocked_circles: Array = []  # {center, radius}
var _walk_coast := PackedVector2Array()
var _built := false


func _ready() -> void:
	build()
	_build_environment()
	_build_sea()
	_build_island()
	_build_terrain()


## Works out the island and its terrain. Safe to call more than once; the
## pathfinding calls it if it needs the terrain before this node is ready.
func build() -> void:
	if _built:
		return
	_built = true
	_load_map()
	coastline = _build_coastline()
	_walk_coast = _offset(coastline, -SHORE_CLEARANCE)
	var c := get_center()
	for lake in LAKES:
		for poly in _mirrored_blob(lake[0], lake[1], lake[2], lake[3]):
			lakes.append(poly)
			_block_poly(poly)
	for plateau in PLATEAUS:
		var blobs: Array = _mirrored_blob(plateau[0], plateau[1], plateau[2], plateau[3])
		var angles: Array = plateau[4] if plateau.size() > 4 else []
		for i in blobs.size():
			var poly: PackedVector2Array = blobs[i]
			plateaus.append(poly)
			if angles.is_empty():
				_block_poly(poly)  # scenery: can't be climbed
				continue
			climbable.append(plateaus.size() - 1)
			_plateau_tops.append(_offset(poly, -CLIFF_BAND))
			_plateau_outer.append(_offset(poly, UNIT_CLEARANCE))
			var dirs: Array = []
			for deg in angles:
				var d: Vector2 = Vector2.from_angle(deg_to_rad(deg))
				dirs.append(d if i == 0 else -d)  # the twin is turned
				if blobs.size() == 1:
					dirs.append(-d)  # in the very middle: its own twin
			for dir in dirs:
				ramps.append({"plateau": plateaus.size() - 1, "edge": _edge_point(poly, dir),
						"dir": dir, "half_width": RAMP_HALF_WIDTH, "length": RAMP_LENGTH})
	for forest in FORESTS:
		var trees := _forest_trees(c + forest[0], forest[1], forest[2])
		var mirrored: Array = []
		for t in trees:
			mirrored.append(2.0 * c - t)
		forests.append({"center": c + forest[0], "radius": forest[1], "trees": trees})
		forests.append({"center": c - forest[0], "radius": forest[1], "trees": mirrored})
		for t in trees + mirrored:
			_blocked_circles.append({"center": t, "radius": TREE_RADIUS + UNIT_CLEARANCE, "tree": true})
	for spot in STONES:
		_blocked_circles.append({"center": c + spot, "radius": 13.0 + UNIT_CLEARANCE})
	for spot in WOODS:
		_blocked_circles.append({"center": c + spot, "radius": 16.0 + UNIT_CLEARANCE})
	for spot in METALS:
		_blocked_circles.append({"center": c + spot, "radius": 5.0 + UNIT_CLEARANCE})


func _load_map() -> void:
	var MatchSetup = load("res://scripts/match_setup.gd")
	if map_id == "":
		map_id = MatchSetup.map
	var m: Dictionary = load("res://scripts/maps.gd").get_map(map_id)
	MatchSetup.built_map = map_id
	island_radius = m.radius
	COAST_WAVES = m.coast
	LAKES = m.lakes
	FORESTS = m.forests
	PLATEAUS = m.plateaus
	hq_offset = m.hq
	army_offset = m.army
	# Resource spots: every one listed gets its mirrored twin too (unless the
	# map lists both already, as the first map does).
	STONES = _with_twins(m.stones)
	WOODS = _with_twins(m.woods)
	METALS = _with_twins(m.metals)


func _with_twins(spots: Array) -> Array:
	var out: Array = []
	for p in spots:
		if not out.has(p):
			out.append(p)
		if not out.has(-p) and not spots.has(-p):
			out.append(-p)
	return out


func _on_plateau_or_ramp(p: Vector2, margin: float) -> bool:
	if ramp_at(p) >= 0:
		return true
	for poly in _plateau_outer:
		if Geometry2D.is_point_in_polygon(p, _offset(poly, margin)):
			return true
	return false


## Where a ray from the middle of a shape in direction `dir` leaves it.
func _edge_point(poly: PackedVector2Array, dir: Vector2) -> Vector2:
	var c: Vector2 = _poly_center(poly)
	var far: Vector2 = c + dir * 1000.0
	for i in poly.size():
		var hit: Variant = Geometry2D.segment_intersects_segment(c, far, poly[i], poly[(i + 1) % poly.size()])
		if hit != null:
			return hit
	return c


## Which ramp (index) a point is on, or -1. On a ramp: from a little inside
## the cliff edge to RAMP_LENGTH out, RAMP_HALF_WIDTH either side.
func ramp_at(p: Vector2) -> int:
	for i in ramps.size():
		var r: Dictionary = ramps[i]
		var rel: Vector2 = p - r.edge
		var along: float = rel.dot(r.dir)
		var side: float = absf(rel.dot(r.dir.orthogonal()))
		if along >= -CLIFF_BAND - 2.0 and along <= r.length and side <= r.half_width:
			return i
	return -1


## Height of the ground (map units): plateau tops are PLATEAU_HEIGHT up,
## ramps slope down from there, everything else is 0.
func height_at(p: Vector2) -> float:
	build()
	var r: int = ramp_at(p)
	if r >= 0:
		var ramp: Dictionary = ramps[r]
		var along: float = (p - ramp.edge).dot(ramp.dir)
		return PLATEAU_HEIGHT * clampf(1.0 - along / ramp.length, 0.0, 1.0)
	for poly in plateaus:
		if Geometry2D.is_point_in_polygon(p, poly):
			return PLATEAU_HEIGHT
	return 0.0


## Is this point up on a plateau or a ramp (no building there)?
func is_raised(p: Vector2) -> bool:
	return height_at(p) > 0.01


## Resource spots on both sides: [{res, pos, radius}] (map units).
## res: 0 stone, 1 wood, 2 metal (matching rock, paper, scissors).
func resource_spots() -> Array:
	build()
	var c := get_center()
	var spots: Array = []
	for spot in STONES:
		spots.append({"res": 0, "pos": c + spot, "radius": 13.0})
	for spot in WOODS:
		spots.append({"res": 1, "pos": c + spot, "radius": 16.0})
	for spot in METALS:
		spots.append({"res": 2, "pos": c + spot, "radius": 5.0})
	# Every forest tree can be cut for wood.
	for forest in forests:
		for t in forest.trees:
			spots.append({"res": 1, "pos": t, "radius": TREE_RADIUS, "tree": true})
	return spots


## Can a ground unit stand here? (On the island, away from the shore, and
## not in a lake, forest tree, plateau or resource prop.) Trees in
## `cut_trees` (positions as keys) have been cut down and no longer block.
func is_walkable(p: Vector2, cut_trees: Dictionary = {}) -> bool:
	if not Geometry2D.is_point_in_polygon(p, _walk_coast):
		return false
	for circle in _blocked_circles:
		if p.distance_squared_to(circle.center) < circle.radius * circle.radius:
			if circle.has("tree") and cut_trees.has(circle.center):
				continue
			return false
	for blocked in _blocked_polys:
		if blocked.box.has_point(p) and Geometry2D.is_point_in_polygon(p, blocked.poly):
			return false
	# Plateaus: the top is open, the cliff edge isn't, except on a ramp.
	for i in _plateau_outer.size():
		if Geometry2D.is_point_in_polygon(p, _plateau_outer[i]) \
				and not Geometry2D.is_point_in_polygon(p, _plateau_tops[i]):
			if ramp_at(p) < 0:
				return false
	return true


## True if a ground point (x, z) is on land. Ground units will use this to
## stay out of the sea; flyers can ignore it.
func is_on_land(ground_point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(ground_point, coastline)


func get_center() -> Vector2:
	return map_size * 0.5


# --- Terrain shapes -----------------------------------------------------------

func _block_poly(poly: PackedVector2Array) -> void:
	var grown := _offset(poly, UNIT_CLEARANCE)
	var box := Rect2(grown[0], Vector2.ZERO)
	for p in grown:
		box = box.expand(p)
	_blocked_polys.append({"poly": grown, "box": box})


## A wobbly oval at `offset` from the centre, plus its mirrored twin
## (just one if it sits on the centre, since it's its own mirror).
func _mirrored_blob(offset: Vector2, rx: float, rz: float, rot: float) -> Array:
	var c := get_center()
	var blob := PackedVector2Array()
	for i in 48:
		var a: float = TAU * i / 48.0
		var wobble: float = 1.0
		for wave in BLOB_WAVES:
			wobble += wave[1] * sin(wave[0] * a + wave[2])
		var local := Vector2(cos(a) * rx, sin(a) * rz) * wobble
		blob.append(c + offset + local.rotated(rot))
	if offset == Vector2.ZERO:
		return [blob]
	var twin := PackedVector2Array()
	for p in blob:
		twin.append(2.0 * c - p)
	return [blob, twin]


## Tree positions in a forest, from a fixed seed (same on every device).
func _forest_trees(center: Vector2, radius: float, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var trees: Array = []
	var inside_shore := _offset(coastline, -12.0)
	for attempt in 400:
		var a: float = rng.randf() * TAU
		var d: float = sqrt(rng.randf()) * (radius - 3.0)
		var p: Vector2 = center + Vector2.from_angle(a) * d
		if not Geometry2D.is_point_in_polygon(p, inside_shore):
			continue
		if _on_plateau_or_ramp(p, 4.0):
			continue  # trees stay off the plateaus and their ramps
		var crowded := false
		for t in trees:
			if p.distance_to(t) < 7.0:
				crowded = true
				break
		if not crowded:
			trees.append(p)
	return trees


# --- Building the world ----------------------------------------------------

func _build_coastline() -> PackedVector2Array:
	var points := PackedVector2Array()
	var center := get_center()
	for i in coast_points:
		var angle: float = TAU * i / coast_points
		var wobble: float = 1.0
		for wave in COAST_WAVES:
			wobble += wave[1] * sin(wave[0] * angle + wave[2])
		points.append(center + Vector2.from_angle(angle) * island_radius * wobble)
	return points


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.55
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 0.5
	# Real-time shadows are off: in the Compatibility renderer they wash the
	# pastel colours out to white, and they're costly on phones. Units get
	# soft blob shadows instead (see units_view.gd), like Ragnarok Online.
	sun.shadow_enabled = false
	add_child(sun)


func _build_sea() -> void:
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = map_size * 6.0
	sea.mesh = plane
	sea.position = Vector3(get_center().x, -2.0, get_center().y)
	sea.material_override = _material(DEEP_SEA)
	add_child(sea)

	_add_flat(_offset(coastline, 22.0), -1.2, SHALLOW_SEA)


func _build_island() -> void:
	var beach: PackedVector2Array = _offset(coastline, 8.0)
	_add_flat(beach, 0.0, SAND)
	_add_skirt(beach, 0.0, -2.5, CLIFF)
	_add_flat(_offset(coastline, -10.0), 0.15, GRASS)
	_add_flat(_offset(coastline, -80.0), 0.3, GRASS_DARK)


func _build_terrain() -> void:
	for lake in lakes:
		_add_flat(_offset(lake, 5.0), 0.36, SAND)
		_add_flat(lake, 0.4, LAKE)
		_add_flat(_offset(lake, -9.0), 0.42, LAKE_DEEP)
	for plateau in plateaus:
		_add_flat(_offset(plateau, 2.5), 0.34, CLIFF)
		_add_skirt(plateau, PLATEAU_HEIGHT, 0.0, CLIFF, _poly_center(plateau))
		_add_flat(plateau, PLATEAU_HEIGHT, PLATEAU_TOP)
	for ramp in ramps:
		_add_ramp(ramp)


## A ramp: a sloped path from the plateau top down to the ground, with its
## sides filled in down to the ground.
func _add_ramp(r: Dictionary) -> void:
	var side: Vector2 = r.dir.orthogonal() * r.half_width
	var top_c: Vector2 = r.edge - r.dir * 1.5  # tucked into the plateau a little
	var low_c: Vector2 = r.edge + r.dir * r.length
	var h: float = PLATEAU_HEIGHT + 0.02
	var t0 := Vector3(top_c.x + side.x, h, top_c.y + side.y)
	var t1 := Vector3(top_c.x - side.x, h, top_c.y - side.y)
	var b0 := Vector3(low_c.x + side.x, 0.45, low_c.y + side.y)
	var b1 := Vector3(low_c.x - side.x, 0.45, low_c.y - side.y)
	var g0 := Vector3(t0.x, 0.0, t0.z)
	var g1 := Vector3(t1.x, 0.0, t1.z)
	# The path (like the plateau top), then its two sides (cliff).
	_add_tris([t0, b1, t1, t0, b0, b1], Vector3.UP, PLATEAU_TOP)
	var out0: Vector3 = Vector3(side.x, 0, side.y).normalized()
	_add_tris([t0, b0, g0], out0, CLIFF)
	_add_tris([t1, g1, b1], -out0, CLIFF)


## Triangles with one colour and normal (drawn from both sides, like the
## rest of the terrain).
func _add_tris(points: Array, normal: Vector3, color: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(normal)
	for v in points:
		st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material(color)
	add_child(mi)


func _multimesh(mesh: Mesh, count: int, material: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	add_child(mmi)
	return mmi


func _poly_center(poly: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in poly:
		sum += p
	return sum / poly.size()


# --- Helpers ---------------------------------------------------------------

func _ground(at: Vector2, height: float) -> Vector3:
	return Vector3(at.x, height, at.y)


func _offset(polygon: PackedVector2Array, amount: float) -> PackedVector2Array:
	var shapes: Array = Geometry2D.offset_polygon(polygon, amount, Geometry2D.JOIN_ROUND)
	return shapes[0] if not shapes.is_empty() else polygon


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## A flat shape lying on the ground at height `y`.
func _add_flat(polygon: PackedVector2Array, y: float, color: Color) -> void:
	var tris: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
	if tris.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for index in tris:
		st.add_vertex(Vector3(polygon[index].x, y, polygon[index].y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material(color)
	add_child(mi)


## Vertical band around a shape's edge (island thickness, plateau cliffs).
func _add_skirt(polygon: PackedVector2Array, top: float, bottom: float, color: Color,
		center: Vector2 = Vector2.INF) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if center == Vector2.INF:
		center = get_center()
	var n: int = polygon.size()
	for i in n:
		var p0: Vector2 = polygon[i]
		var p1: Vector2 = polygon[(i + 1) % n]
		var out: Vector2 = ((p0 + p1) * 0.5 - center).normalized()
		st.set_normal(Vector3(out.x, 0, out.y))
		var a := Vector3(p0.x, top, p0.y)
		var b := Vector3(p1.x, top, p1.y)
		var c := Vector3(p1.x, bottom, p1.y)
		var d := Vector3(p0.x, bottom, p0.y)
		for v in [a, b, c, a, c, d]:
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material(color)
	add_child(mi)
