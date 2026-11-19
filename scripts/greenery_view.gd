extends Node3D
## Little plants scattered over the grass (tufts, flowers, bushes) so the
## grassland doesn't look bare. Looks only: they don't block anything, and
## they're hidden where a building stands. Placed in patches from a fixed
## seed, so a map always looks the same.

const PLANTS := [
	["grass_1", 7.0, 10, true], ["grass_2", 6.0, 10, true], ["flowers_pink", 7.0, 3, false],
	["flowers_white", 7.0, 3, false], ["flowers_lilac", 7.0, 2, false], ["bush", 8.0, 2, false],
]  # picture, height (map units), how common, tinted by the ground under it
## Tinted plants: this much darker than the ground they grow on.
const TINT_DARKEN := 0.08
## Patches of plants, and plants per patch (at most).
const PATCHES := 150
const PER_PATCH := 7
## Keep clear of resource spots and buildings by this much more than their size.
const CLEAR := 3.0

var sim: Node
var field: Node3D
var _batches: Array = []   # MultiMeshInstance3D per picture
var _spots: Array = []     # per picture: [{pos: Vector3, scale: float}]
var _seen_buildings := -1


func setup(the_sim: Node, the_field: Node3D) -> void:
	sim = the_sim
	field = the_field
	process_mode = Node.PROCESS_MODE_ALWAYS
	_place()
	for i in PLANTS.size():
		_batches.append(_make_batch(i))
	_hide_under_buildings()


func _process(_delta: float) -> void:
	if sim != null and sim.buildings.size() != _seen_buildings:
		_hide_under_buildings()


## Where everything goes: patches round random spots on the grass.
func _place() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(field.map_id) if "map_id" in field else 7
	for i in PLANTS.size():
		_spots.append([])
	var grass: PackedVector2Array = field._shore_ring("grass", -3.0)
	var box := Rect2(grass[0], Vector2.ZERO)
	for p in grass:
		box = box.expand(p)
	var weights := 0
	for plant in PLANTS:
		weights += plant[2]
	var made := 0
	var tries := 0
	# As many patches for the island's size (the full count on a 330 island).
	var patches: int = roundi(PATCHES * pow(field.island_radius / 330.0, 2.0))
	while made < patches and tries < patches * 20:
		tries += 1
		var c := Vector2(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y))
		if not _open(c, grass):
			continue
		made += 1
		# A patch is mostly one kind, with a few others mixed in.
		var main: int = _pick(rng, weights)
		for k in rng.randi_range(2, PER_PATCH):
			var p: Vector2 = c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 10.0)
			if not _open(p, grass):
				continue
			var kind: int = main if rng.randf() < 0.7 else _pick(rng, weights)
			var h: float = field.height_at(p)
			_spots[kind].append({"pos": Vector3(p.x, h, p.y), "scale": rng.randf_range(0.75, 1.2),
					"tint": _ground_tint(p, h)})


## The ground colour where a plant grows, a little darker.
func _ground_tint(p: Vector2, h: float) -> Color:
	var ground: Color = field._ground_colour(p)
	if h > field.PLATEAU_HEIGHT * 1.5:
		ground = field.PLATEAU_TOP.lightened(0.18)
	elif h > 0.5:
		ground = field.PLATEAU_TOP
	return ground.darkened(TINT_DARKEN)


func _pick(rng: RandomNumberGenerator, weights: int) -> int:
	var r: int = rng.randi_range(0, weights - 1)
	for i in PLANTS.size():
		r -= PLANTS[i][2]
		if r < 0:
			return i
	return 0


## On grass, somewhere a hand could stand, and not on a resource spot.
func _open(p: Vector2, grass: PackedVector2Array) -> bool:
	if not Geometry2D.is_point_in_polygon(p, grass) or not field.is_walkable(p):
		return false
	if field.is_slope_or_edge(p):
		return false
	for n in sim.nodes:
		var r: float = n.radius / float(sim.SCALE) + CLEAR
		if p.distance_squared_to(Vector2(n.x, n.z) / float(sim.SCALE)) < r * r:
			return false
	return true


func _make_batch(i: int) -> MultiMeshInstance3D:
	var tex: Texture2D = load("res://assets/env/plant_%s.png" % PLANTS[i][0])
	var height: float = PLANTS[i][1]
	var quad := QuadMesh.new()
	quad.size = Vector2(height * tex.get_width() / tex.get_height(), height)
	quad.center_offset = Vector3(0, height * 0.5 - 0.15, 0)  # base just into the ground
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Cut-out edges (no sorting needed, cheap even with hundreds), kept
	# crisp as it shrinks.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.4
	mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var tinted: bool = PLANTS[i][3]
	mat.vertex_color_use_as_albedo = tinted
	mat.vertex_color_is_srgb = tinted
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = tinted
	mm.mesh = quad
	mm.instance_count = _spots[i].size()
	if tinted:
		for k in _spots[i].size():
			mm.set_instance_color(k, _spots[i][k].tint)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


## Shows every plant except those where a building now stands.
func _hide_under_buildings() -> void:
	_seen_buildings = sim.buildings.size()
	for i in _batches.size():
		var mm: MultiMesh = _batches[i].multimesh
		for k in _spots[i].size():
			var s: Dictionary = _spots[i][k]
			var under := false
			for b in sim.buildings:
				var r: float = b.radius / float(sim.SCALE) + CLEAR
				if Vector2(s.pos.x, s.pos.z).distance_squared_to(Vector2(b.x, b.z) / float(sim.SCALE)) < r * r:
					under = true
					break
			s.shown = not under
			mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * (0.0 if under else s.scale)), s.pos))


## How many plants there are (for tests).
func count() -> int:
	var n := 0
	for list in _spots:
		n += list.size()
	return n


## How many are showing (for tests).
func showing() -> int:
	var n := 0
	for list in _spots:
		for s in list:
			if s.get("shown", true):
				n += 1
	return n
