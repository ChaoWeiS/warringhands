extends Node3D
## Draws the resource spots from the simulation:
##
##   Stone (rocks gather fastest):    rock piles.
##   Wood (papers gather fastest):    every forest tree, plus lumber camps
##                                    (pines with a log pile).
##   Metal (scissors gather fastest): crystal clusters on rocks.
##
## Stone, metal and lumber camps are just their pictures (no badges). Forest trees are drawn in
## two batches (one per pine picture) so the hundreds of them stay cheap; a
## tree that's been cut down shrinks away, and its ground opens up.

const UI := preload("res://scripts/ui_style.gd")
const GroundShadow := preload("res://scripts/ground_shadow.gd")
const PINES := [preload("res://assets/env/pine_1.png"), preload("res://assets/env/pine_2.png")]
const CRYSTALS := [preload("res://assets/env/crystals_1.png"), preload("res://assets/env/crystals_2.png")]
const ROCKS := [preload("res://assets/env/rocks_1.png"), preload("res://assets/env/rocks_2.png")]

@export var sim_path: NodePath

const TRUNK := Color("#d9b48f")
const LOG_END := Color("#f3dcb8")
## Forest tree height (map units), varied per tree by this much either way.
const TREE_HEIGHT := 17.0
const TREE_VARY := 0.18
## Height (map units) of each kind of spot, for its badge and for tapping.
const TOPS := [12.0, 19.0, 24.0]
const BADGE_GAP := 3.0
const FADE := 0.8

var sim: Node
var _views: Dictionary = {}  # node id -> {root, label} (or {tree, batch, index, pos, height})
var _batches: Array = []     # MultiMeshInstance3D per pine picture
var _batch_used: Array = [0, 0]


func _ready() -> void:
	sim = get_node(sim_path)
	for i in PINES.size():
		_batches.append(_make_batch(PINES[i]))
	_sync()


func _process(_delta: float) -> void:
	_sync()


## Top of a spot (map units), for tapping it on screen.
static func top_of(n: Dictionary) -> float:
	return TREE_HEIGHT if n.get("tree", false) else TOPS[n.res]


func _sync() -> void:
	var alive := {}
	for n in sim.nodes:
		alive[n.id] = true
		var view: Dictionary = _views.get(n.id, {})
		if view.is_empty():
			view = _make_tree(n) if n.get("tree", false) else _make(n)
			_views[n.id] = view
	for id in _views.keys():
		if not alive.has(id):
			_remove(_views[id])
			_views.erase(id)


# --- Forest trees --------------------------------------------------------------

func _make_batch(texture: Texture2D) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	var aspect: float = float(texture.get_width()) / texture.get_height()
	quad.size = Vector2(TREE_HEIGHT * aspect, TREE_HEIGHT)
	quad.center_offset = Vector3(0, TREE_HEIGHT * 0.5, 0)  # stands on its base
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = 256
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	return mmi


func _make_tree(n: Dictionary) -> Dictionary:
	var pos := Vector3(n.x, 0, n.z) / float(sim.SCALE)
	# Picture and size vary per tree, fixed by position.
	var h: int = absi(n.x * 31 + n.z * 17) / 7
	var batch: int = h % PINES.size()
	var size: float = 1.0 - TREE_VARY + 2.0 * TREE_VARY * float(h % 97) / 96.0
	var mm: MultiMesh = _batches[batch].multimesh
	var index: int = _batch_used[batch]
	if index >= mm.instance_count:
		# More trees than room: grow the batch, keeping what's there.
		var keep: Array = []
		for i in index:
			keep.append(mm.get_instance_transform(i))
		mm.instance_count = index * 2
		for i in index:
			mm.set_instance_transform(i, keep[i])
	_batch_used[batch] = index + 1
	mm.visible_instance_count = index + 1
	mm.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ONE * size), pos))
	# Soft shadow on the ground (the same look as everything else's).
	# Trees: wider and stronger, centred on the trunk (the crown hides
	# anything further back).
	var shadow: MeshInstance3D = GroundShadow.make(5.5 * size, 0.75, 0.42, 0.05)
	shadow.position += pos
	add_child(shadow)
	return {"tree": true, "batch": batch, "index": index, "pos": pos, "size": size, "shadow": shadow}


## A cut-down tree: hide it in its batch and let a stand-in shrink away.
func _remove_tree(view: Dictionary) -> void:
	var mm: MultiMesh = _batches[view.batch].multimesh
	mm.set_instance_transform(view.index, Transform3D(Basis().scaled(Vector3.ZERO), view.pos))
	var stand_in := Sprite3D.new()
	var tex: Texture2D = PINES[view.batch]
	stand_in.texture = tex
	stand_in.pixel_size = TREE_HEIGHT * view.size / tex.get_height()
	stand_in.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	stand_in.shaded = false
	stand_in.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	stand_in.offset = Vector2(0, tex.get_height() * 0.5)
	stand_in.position = view.pos
	add_child(stand_in)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(stand_in, "scale", Vector3(1.1, 0.05, 1.0), FADE).set_ease(Tween.EASE_IN)
	tween.tween_property(stand_in, "modulate:a", 0.0, FADE)
	tween.tween_property(view.shadow, "scale", Vector3.ZERO, FADE)
	tween.chain().tween_callback(func():
		stand_in.queue_free()
		view.shadow.queue_free())


# --- Stone, metal, lumber camps -------------------------------------------------

func _make(n: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.position = Vector3(n.x / float(sim.SCALE), 0, n.z / float(sim.SCALE))
	add_child(root)

	match n.res:
		0: _make_stone(root)
		1: _make_camp(root)
		2: _make_metal(root)

	return {"root": root}


## Two rock piles, the bigger one behind.
func _make_stone(root: Node3D) -> void:
	_picture(root, ROCKS[0], 20.0, Vector3(-3, 0, -3))
	_picture(root, ROCKS[1], 15.0, Vector3(5, 0, 4))


## Pines around a log pile.
func _make_camp(root: Node3D) -> void:
	for t in [[Vector2(-8, -7), 1.0], [Vector2(8, -9), 0.9], [Vector2(-10, 7), 0.85]]:
		var tex: Texture2D = PINES[0 if t[1] > 0.88 else 1]
		var pine := _picture(root, tex, TREE_HEIGHT * t[1] * float(tex.get_width()) / tex.get_height(),
				Vector3(t[0].x, 0, t[0].y))
		pine.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	# Stump.
	var stump := _cylinder(1.6, 1.9, 2.0, TRUNK)
	stump.position = Vector3(9, 1.0, 8)
	root.add_child(stump)
	# Log pile: three logs with two on top, turned so the cut ends show.
	var pile := Node3D.new()
	pile.position = Vector3(1, 0, 3)
	pile.rotation.y = -0.6
	root.add_child(pile)
	var logs := [[-2.7, 1.3], [0.0, 1.3], [2.7, 1.3], [-1.35, 3.6], [1.35, 3.6]]
	for l in logs:
		var log := _cylinder(1.35, 1.35, 9.0, TRUNK)
		log.rotation = Vector3(0, 0, PI / 2)
		log.position = Vector3(0, l[1], l[0])
		pile.add_child(log)
		for side in [-1, 1]:
			var cap := _cylinder(1.1, 1.1, 0.1, LOG_END)
			cap.rotation = Vector3(0, 0, PI / 2)
			cap.position = Vector3(side * 4.55, l[1], l[0])
			pile.add_child(cap)


## Two crystal clusters on rocks.
func _make_metal(root: Node3D) -> void:
	_picture(root, CRYSTALS[0], 13.0, Vector3(-2.5, 0, 1.5))
	_picture(root, CRYSTALS[1], 10.0, Vector3(3.5, 0, 5.0))


func _remove(view: Dictionary) -> void:
	if view.has("tree"):
		_remove_tree(view)
		return
	var root: Node3D = view.root
	var tween := create_tween()
	tween.tween_property(root, "scale", Vector3(1.0, 0.05, 1.0), FADE).set_ease(Tween.EASE_IN)
	tween.tween_callback(root.queue_free)


# --- Helpers ------------------------------------------------------------------

## A picture standing on the ground, facing the camera, `width` map units wide.
func _picture(root: Node3D, tex: Texture2D, width: float, at: Vector3) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = width / tex.get_width()
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.offset = Vector2(0, tex.get_height() * 0.5)
	s.position = at
	root.add_child(s)
	# Its own shadow, tucked in under its base.
	var shade: MeshInstance3D = GroundShadow.make(width * 0.5, 0.5)
	shade.position += Vector3(at.x, 0, at.z)
	root.add_child(shade)
	return s


func _cylinder(top: float, bottom: float, height: float, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = top
	cyl.bottom_radius = bottom
	cyl.height = height
	cyl.radial_segments = 10
	m.mesh = cyl
	m.material_override = _material(color, false)
	return m


func _material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
