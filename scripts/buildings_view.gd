extends Node3D
## Draws buildings from the simulation: pastel models with team-coloured
## roofs, rising from the ground while under construction, an HP bar once
## damaged, a ring when selected, and a collapse when destroyed.
##
##   HQ (town hall), Quarry, Mill, Forge: painted art (assets/env/), on a
##   patch of the team's colour. The factories make rocks, papers and scissors.

@export var sim_path: NodePath

const TEAM_COLORS := [Color("#ff7f9a"), Color("#6fb6ff")]
const TRIM := Color("#e2cfae")
const STONE := Color("#c9c3d6")
const HP_BAR_BG := Color(0.25, 0.22, 0.33, 0.85)
const HP_BAR_PX := Vector2(160, 14)
const PIXEL := 0.06
const ART := {
	"hq": preload("res://assets/env/hq.png"),
	"quarry": preload("res://assets/env/quarry.png"),
	"mill": preload("res://assets/env/mill.png"),
	"forge": preload("res://assets/env/forge.png"),
}
## Width of each building's picture (map units).
const ART_WIDTH := {"hq": 30.0, "quarry": 23.0, "mill": 23.0, "forge": 23.0}

var sim: Node
var _views: Dictionary = {}  # building id -> {root, model, ring, hp_bg, hp_fill, sails}
var _selected_id := 0
var _white: ImageTexture


func _ready() -> void:
	sim = get_node(sim_path)
	var img := Image.create(int(HP_BAR_PX.x), int(HP_BAR_PX.y), false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(img)
	sim.building_added.connect(_on_added)
	sim.building_destroyed.connect(_on_destroyed)
	sim.unit_hit.connect(_on_hit)
	for b in sim.buildings:
		_on_added(b.id)


func _process(delta: float) -> void:
	for b in sim.buildings:
		var view: Dictionary = _views.get(b.id, {})
		if view.is_empty():
			continue
		var spec: Dictionary = sim.BUILDINGS[b.btype]
		var done: float = 1.0 if spec.build == 0 else clampf(float(b.progress) / spec.build, 0.0, 1.0)
		# Under construction: grows up out of the ground.
		view.model.scale = Vector3(1.0, 0.15 + 0.85 * done, 1.0)
		view.scaffold.visible = done < 1.0
		if view.sails != null and done >= 1.0:
			view.sails.rotate_z(delta * (2.2 if not b.queue.is_empty() else 0.6))
		var damaged: bool = b.hp < b.max_hp
		view.hp_bg.visible = damaged
		view.hp_fill.visible = damaged
		if damaged:
			var width: int = maxi(1, int(HP_BAR_PX.x * b.hp / b.max_hp))
			view.hp_fill.region_rect = Rect2(0, 0, width, HP_BAR_PX.y)


func set_selected_building(id: int) -> void:
	_selected_id = id
	for bid in _views:
		_views[bid].ring.visible = bid == id


func _on_added(id: int) -> void:
	var b: Dictionary = sim.get_entity(id)
	if b.is_empty() or _views.has(id):
		return
	var r: float = b.radius / float(sim.SCALE)
	var root := Node3D.new()
	root.position = Vector3(b.x / float(sim.SCALE), 0, b.z / float(sim.SCALE))
	add_child(root)
	var model := Node3D.new()
	root.add_child(model)
	var roof: Color = TEAM_COLORS[b.team]
	var sails: Node3D = null
	match b.btype:
		"hq", "quarry", "mill", "forge":
			# Painted art, standing up and facing the camera, on a patch of
			# the team's colour.
			var tex: Texture2D = ART[b.btype]
			var art := Sprite3D.new()
			art.texture = tex
			art.pixel_size = ART_WIDTH[b.btype] / tex.get_width()
			art.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			art.shaded = false
			art.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
			art.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			art.offset = Vector2(0, tex.get_height() * 0.5)
			art.position = Vector3(0, 0, r * (1.0 if b.btype == "hq" else 0.15))
			model.add_child(art)
			var patch := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = r + 1.0
			disc.bottom_radius = r + 1.0
			disc.height = 0.02
			disc.radial_segments = 32
			patch.mesh = disc
			patch.position.y = 0.5
			var team_mat := _mat(Color(roof, 0.55))
			team_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			team_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			patch.material_override = team_mat
			root.add_child(patch)
	# Scaffold ring while under construction.
	var scaffold := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = r + 0.3
	torus.outer_radius = r + 0.9
	scaffold.mesh = torus
	scaffold.position.y = 0.5
	scaffold.material_override = _mat(TRIM)
	root.add_child(scaffold)
	# Selection ring.
	var ring := MeshInstance3D.new()
	var sel := TorusMesh.new()
	sel.inner_radius = r + 1.2
	sel.outer_radius = r + 1.9
	ring.mesh = sel
	ring.position.y = 0.5
	ring.material_override = _mat(Color.WHITE)
	ring.visible = id == _selected_id
	root.add_child(ring)
	var hp_bg := _bar(HP_BAR_BG, true, 33.0 if b.btype == "hq" else 25.0)
	var hp_fill := _bar(TEAM_COLORS[b.team].lightened(0.15), false, 33.0 if b.btype == "hq" else 25.0)
	hp_fill.render_priority = 2
	root.add_child(hp_bg)
	root.add_child(hp_fill)
	_views[id] = {"root": root, "model": model, "ring": ring, "scaffold": scaffold,
			"hp_bg": hp_bg, "hp_fill": hp_fill, "sails": sails}


func _on_destroyed(id: int) -> void:
	var view: Dictionary = _views.get(id, {})
	if view.is_empty():
		return
	_views.erase(id)
	view.hp_bg.visible = false
	view.hp_fill.visible = false
	view.ring.visible = false
	var tween := create_tween()
	tween.tween_property(view.model, "scale", Vector3(1.1, 0.05, 1.1), 0.8).set_ease(Tween.EASE_IN)
	tween.tween_callback(view.root.queue_free)


func _on_hit(target_id: int, _attacker: int, damage: int, _strength: int) -> void:
	var view: Dictionary = _views.get(target_id, {})
	if view.is_empty():
		return
	var label := Label3D.new()
	label.text = "-%d" % damage
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 3
	label.font_size = 80
	label.outline_size = 16
	label.outline_modulate = Color(0.3, 0.22, 0.35)
	label.pixel_size = 0.03
	label.position = view.root.position + Vector3(randf_range(-3, 3), 12.0, 0)
	add_child(label)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 4.0, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


# --- Little model helpers ------------------------------------------------------

func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color)
	parent.add_child(mi)
	return mi


func _cylinder(parent: Node3D, top: float, bottom: float, height: float, y: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 16
	mi.mesh = mesh
	mi.position = Vector3(0, y, 0)
	mi.material_override = _mat(color)
	parent.add_child(mi)
	return mi


func _cone(parent: Node3D, radius: float, height: float, y: float, color: Color) -> MeshInstance3D:
	return _cylinder(parent, 0.05, radius, height, y, color)


func _sphere(parent: Node3D, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 5
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color)
	parent.add_child(mi)
	return mi


## A gabled roof (a prism) sitting on walls of height `base`.
func _roof(parent: Node3D, width: float, depth: float, height: float, base: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(width, height, depth)
	mi.mesh = mesh
	mi.position = Vector3(0, base + height * 0.5, 0)
	# Ridge runs left-right, so the camera sees the sloped faces.
	mi.rotation.y = PI / 2.0
	mi.mesh.size = Vector3(depth, height, width)
	mi.material_override = _mat(color)
	parent.add_child(mi)


func _bar(color: Color, back: bool, height: float) -> Sprite3D:
	var bar := Sprite3D.new()
	bar.texture = _white
	bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bar.pixel_size = PIXEL
	bar.modulate = color
	bar.shaded = false
	bar.no_depth_test = true
	bar.render_priority = 1
	bar.position = Vector3(0, height, 0)
	if not back:
		bar.centered = false
		bar.offset = -HP_BAR_PX * 0.5
		bar.region_enabled = true
		bar.region_rect = Rect2(Vector2.ZERO, HP_BAR_PX)
	bar.visible = false
	return bar
