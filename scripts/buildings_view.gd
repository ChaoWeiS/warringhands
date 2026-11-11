extends Node3D
## Draws buildings from the simulation: pastel models with team-coloured
## roofs, rising from the ground while under construction, an HP bar once
## damaged, a ring when selected, and a collapse when destroyed.
##
##   HQ (town hall), Quarry, Mill, Forge: painted art (assets/env/), on a
##   patch of the team's colour. The factories make rocks, papers and scissors.

@export var sim_path: NodePath

## A construction just finished (shown once per building).
signal finished(building_id: int)

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
## The red team's town hall: flag, banners and windows red instead of blue.
const HQ_RED := preload("res://assets/env/hq_red.png")
## How far in front of the footprint's centre a picture's bottom edge sits,
## as a share of its width.
const ART_BASE_DEPTH := 0.33
## Width of each building's picture (map units).
const ART_WIDTH := {"hq": 30.0, "quarry": 23.0, "mill": 23.0, "forge": 23.0}

var sim: Node
var _views: Dictionary = {}  # building id -> {root, model, ring, hp_bg, hp_fill, sails}
var _selected_ids: Array = []
var _ghost: Node3D = null        # placement preview
var _ghost_type := ""
const GHOST_ALPHA := 0.5
var _ranges := Node3D.new()   # build range circles, shown while placing
var _range_key := ""          # which buildings the circles were drawn for
const RANGE_COLOR := Color(1, 1, 1, 0.16)
const RANGE_EDGE := Color(1, 1, 1, 0.85)
var _white: ImageTexture


func _ready() -> void:
	sim = get_node(sim_path)
	_ranges.visible = false
	add_child(_ranges)
	var img := Image.create(int(HP_BAR_PX.x), int(HP_BAR_PX.y), false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(img)
	sim.building_added.connect(_on_added)
	sim.building_destroyed.connect(_on_destroyed)
	sim.unit_hit.connect(_on_hit)
	sim.building_repaired.connect(_on_repaired)
	for b in sim.buildings:
		_on_added(b.id)


func _process(delta: float) -> void:
	for b in sim.buildings:
		var view: Dictionary = _views.get(b.id, {})
		if view.is_empty():
			continue
		var spec: Dictionary = sim.BUILDINGS[b.btype]
		var done: float = 1.0 if spec.build == 0 else clampf(float(b.progress) / spec.build, 0.0, 1.0)
		if done >= 1.0 and view.get("building", false):
			finished.emit(b.id)
		view.building = done < 1.0
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


## While placing a building: circles around the team's buildings showing
## where it may go.
func show_build_range(team: int, on: bool) -> void:
	_ranges.visible = on
	if not on:
		return
	var key := ""
	for b in sim.buildings:
		if b.team == team:
			key += "%d," % b.id
	if key == _range_key:
		return
	_range_key = key
	for c in _ranges.get_children():
		c.queue_free()
	var reach: float = sim.BUILD_RANGE / float(sim.SCALE)
	var fill := _mat(RANGE_COLOR)
	fill.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var edge := _mat(RANGE_EDGE)
	edge.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for b in sim.buildings:
		if b.team != team:
			continue
		var at := Vector3(b.x / float(sim.SCALE), 0, b.z / float(sim.SCALE))
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = reach
		cyl.bottom_radius = reach
		cyl.height = 0.02
		cyl.radial_segments = 64
		disc.mesh = cyl
		disc.position = at + Vector3(0, 0.55, 0)
		disc.material_override = fill
		_ranges.add_child(disc)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = reach - 0.4
		torus.outer_radius = reach + 0.4
		torus.rings = 64
		ring.mesh = torus
		ring.scale = Vector3(1, 0.2, 1)
		ring.position = at + Vector3(0, 0.6, 0)
		ring.material_override = edge
		_ranges.add_child(ring)


## Where a building's picture is on screen in a pane (empty if none).
func screen_rect(camera: Camera3D, id: int) -> Rect2:
	var view: Dictionary = _views.get(id, {})
	if view.is_empty() or view.art == null:
		return Rect2()
	var art: Sprite3D = view.art
	var size: Vector2 = Vector2(art.texture.get_size()) * art.pixel_size  # map units
	var base: Vector3 = art.global_position
	var foot: Vector2 = camera.unproject_position(base)
	var head: Vector2 = camera.unproject_position(base + Vector3(0, size.y, 0))
	var half: float = size.x * 0.5 / camera.units_per_pixel
	return Rect2(foot.x - half, head.y, half * 2.0, foot.y - head.y)


## Placing a building: a see-through preview where it would go (red if it
## can't go there).
func show_ghost(btype: String, team: int, at: Vector2, ok: bool) -> void:
	if _ghost == null or _ghost_type != btype:
		hide_ghost()
		_ghost = Node3D.new()
		_ghost_type = btype
		add_child(_ghost)
		var tex: Texture2D = HQ_RED if btype == "hq" and team == 0 else ART[btype]
		var art := Sprite3D.new()
		art.texture = tex
		art.pixel_size = ART_WIDTH[btype] / tex.get_width()
		art.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		art.shaded = false
		art.transparent = true
		art.no_depth_test = true
		art.render_priority = 4
		art.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		art.offset = Vector2(0, tex.get_height() * 0.5)
		art.position = Vector3(0, 0, ART_WIDTH[btype] * ART_BASE_DEPTH)
		art.name = "Art"
		_ghost.add_child(art)
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		var r: float = sim.BUILDINGS[btype].radius / float(sim.SCALE)
		cyl.top_radius = r
		cyl.bottom_radius = r
		cyl.height = 0.02
		cyl.radial_segments = 32
		disc.mesh = cyl
		disc.position.y = 0.6
		disc.name = "Footprint"
		var mat := _mat(Color.WHITE)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		disc.material_override = mat
		_ghost.add_child(disc)
	_ghost.position = Vector3(at.x, 0, at.y)
	_ghost.visible = true
	var tint: Color = Color(1, 1, 1, GHOST_ALPHA) if ok else Color(1, 0.45, 0.45, GHOST_ALPHA)
	(_ghost.get_node("Art") as Sprite3D).modulate = tint
	(_ghost.get_node("Footprint") as MeshInstance3D).material_override.albedo_color = \
			Color(0.6, 1, 0.6, 0.35) if ok else Color(1, 0.4, 0.4, 0.35)


func hide_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
		_ghost_type = ""


func ghost_visible() -> bool:
	return _ghost != null and _ghost.visible


func set_selected_buildings(ids: Array) -> void:
	_selected_ids = ids.duplicate()
	for bid in _views:
		_views[bid].ring.visible = _selected_ids.has(bid)


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
	var art: Sprite3D = null
	match b.btype:
		"hq", "quarry", "mill", "forge":
			# Painted art, standing up and facing the camera, on a patch of
			# the team's colour.
			var tex: Texture2D = HQ_RED if b.btype == "hq" and b.team == 0 else ART[b.btype]
			art = Sprite3D.new()
			art.texture = tex
			art.pixel_size = ART_WIDTH[b.btype] / tex.get_width()
			art.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			art.shaded = false
			art.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
			art.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			art.offset = Vector2(0, tex.get_height() * 0.5)
			# The picture's drawn base (an isometric diamond about a third of
			# its width deep) is centred on the footprint.
			art.position = Vector3(0, 0, ART_WIDTH[b.btype] * ART_BASE_DEPTH)
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
	ring.visible = _selected_ids.has(id)
	root.add_child(ring)
	var hp_bg := _bar(HP_BAR_BG, true, 33.0 if b.btype == "hq" else 25.0)
	var hp_fill := _bar(TEAM_COLORS[b.team].lightened(0.15), false, 33.0 if b.btype == "hq" else 25.0)
	hp_fill.render_priority = 2
	root.add_child(hp_bg)
	root.add_child(hp_fill)
	_views[id] = {"root": root, "model": model, "ring": ring, "scaffold": scaffold,
			"hp_bg": hp_bg, "hp_fill": hp_fill, "sails": sails, "art": art,
			"building": b.progress < sim.BUILDINGS[b.btype].build}  # under construction


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
	_float_number(target_id, "-%d" % damage, Color.WHITE)


func _on_repaired(building_id: int, amount: int) -> void:
	_float_number(building_id, "+%d" % amount, Color("#9ff0b0"))


## A number that floats up from a building and fades.
func _float_number(building_id: int, text: String, color: Color) -> void:
	var view: Dictionary = _views.get(building_id, {})
	if view.is_empty():
		return
	var label := Label3D.new()
	label.text = text
	label.modulate = color
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
