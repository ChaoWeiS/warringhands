extends Node3D
## Draws the units from the simulation: animated 2D hand sprites standing on
## the 3D world (always facing the camera), Ragnarok-style, with a soft
## team-coloured base under each, a selection ring, and a marker where a move
## order was given. In combat: attack animation when swinging, crying defend
## animation when hit, HP bars once damaged, floating damage numbers, and a
## fade-out when a unit dies.
##
## It only reads the sim (and listens to its hit / death signals) and smooths
## positions between ticks. Units added mid-game get visuals automatically.
##
## Sprites: assets/units/hands.png, cut from art_source/hands_sheet.png by
## tools/cut_hand_sprites.py. 5 frames per row, 128 px cells;
## row = kind * 3 + state (kind: rock, paper, scissors; state: idle, attack, defend).

@export var sim_path: NodePath

const ATLAS := preload("res://assets/units/hands.png")
const CELL := 128
const FRAMES := 5
const STATES := ["idle", "attack", "defend"]
const STATE_FPS := {"idle": 6.0, "attack": 10.0, "defend": 8.0}

## Team colours, used for the base under each unit.
const TEAM_COLORS := [Color("#ff7f9a"), Color("#6fb6ff")]
const RING_COLOR := Color("#ffffff")
const MARKER_COLOR := Color("#fff3b0")
## Map units per sprite pixel (a hand is about 6 map units tall).
const SPRITE_PIXEL_SIZE := 0.06
## Height of the hand's middle above the ground, for picking.
const SPRITE_HEIGHT := 3.0
## Walking hops: how high (map units) and how many per second.
const HOP_HEIGHT := 1.6
const HOPS_PER_SECOND := 2.7
## How much the team base shrinks at the top of a hop (like a shadow).
const HOP_BASE_SHRINK := 0.25
## A little squash on landing and stretch in the air.
const HOP_SQUASH := 0.08
## Route lines drawn for selected units: dashed ribbons on the ground.
const ROUTE_COLOR := Color(1, 1, 1, 0.75)
const ROUTE_WIDTH := 0.6
const ROUTE_DASH := 2.2
const ROUTE_GAP := 1.6
## Combat look.
const HURT_TICKS := 12      # play "defend" this long after being hit
const SWING_TICKS := 14     # play "attack" this long after swinging
const HP_BAR_PX := Vector2(90, 10)   # in sprite pixels
const HP_BAR_HEIGHT := 8.4           # above the ground (map units)
const HP_BAR_BG := Color(0.25, 0.22, 0.33, 0.85)
const DAMAGE_COLORS := {1: Color("#ff5a6e"), 0: Color("#ffffff"), -1: Color("#d9d4e6")}
const DAMAGE_SIZES := {1: 115, 0: 85, -1: 68}

var sim: Node
var _views: Dictionary = {}  # unit id -> {root, ring, sprite, base, hop}
var _selected: Dictionary = {}
var _frames_by_kind: Array = []  # SpriteFrames per kind
var _routes_mesh := ImmediateMesh.new()
var _white: ImageTexture


func _ready() -> void:
	sim = get_node(sim_path)
	var img := Image.create(int(HP_BAR_PX.x), int(HP_BAR_PX.y), false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(img)
	for kind in 3:
		_frames_by_kind.append(_build_frames(kind))
	sim.unit_hit.connect(_on_unit_hit)
	sim.unit_died.connect(_on_unit_died)
	for u in sim.units:
		_make_view(u)
	var routes := MeshInstance3D.new()
	routes.mesh = _routes_mesh
	routes.material_override = _flat_material(ROUTE_COLOR, true)
	routes.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(routes)
	_update_positions()


func _process(delta: float) -> void:
	_update_positions()
	_update_hops(delta)
	_update_combat_look()
	_draw_routes()


## Where a unit is drawn right now (middle of its sprite), for picking.
func world_position(id: int) -> Vector3:
	var view: Dictionary = _views.get(id, {})
	if view.is_empty():
		return Vector3.ZERO
	return view.root.position + Vector3(0, SPRITE_HEIGHT, 0)


func set_selected(ids: Array) -> void:
	_selected.clear()
	for id in ids:
		_selected[id] = true
	for id in _views:
		_views[id].ring.visible = _selected.has(id)


## Plays "idle", "attack" or "defend" for a unit right away. (During play the
## animation follows combat automatically each frame.)
func set_state(id: int, state: String) -> void:
	var view: Dictionary = _views.get(id, {})
	if not view.is_empty() and view.sprite.animation != state:
		view.sprite.play(state)


## A ring that shrinks and fades where a move order was given.
func show_move_marker(ground: Vector3) -> void:
	var marker := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 5.0
	torus.outer_radius = 6.2
	marker.mesh = torus
	var mat := _flat_material(MARKER_COLOR, true)
	marker.material_override = mat
	marker.position = Vector3(ground.x, 0.6, ground.z)
	add_child(marker)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(marker, "scale", Vector3(0.3, 1, 0.3), 0.6)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tween.chain().tween_callback(marker.queue_free)


func _update_positions() -> void:
	var t: float = sim.tick_fraction()
	var scale_factor: float = float(sim.SCALE)
	for u in sim.units:
		var view: Dictionary = _views.get(u.id, {})
		if view.is_empty():
			_make_view(u)  # a unit added mid-game
			view = _views[u.id]
		var x: float = lerpf(u.px, u.x, t) / scale_factor
		var z: float = lerpf(u.pz, u.z, t) / scale_factor
		view.root.position = Vector3(x, 0, z)
		# Face the way we're walking (the art faces right).
		if u.x != u.px:
			view.sprite.flip_h = u.x < u.px


## Attack / defend / idle animations, facing the enemy, and HP bars.
func _update_combat_look() -> void:
	for u in sim.units:
		var view: Dictionary = _views.get(u.id, {})
		if view.is_empty():
			continue
		var state := "idle"
		if sim.tick - u.hurt_tick < HURT_TICKS:
			state = "defend"
		elif u.target != 0 and sim.tick - u.attack_tick < SWING_TICKS:
			state = "attack"
		if view.sprite.animation != state:
			view.sprite.play(state)
		var foe: Dictionary = sim.get_unit(u.target)
		if not foe.is_empty() and not u.moving:
			view.sprite.flip_h = foe.x < u.x
		var damaged: bool = u.hp < sim.MAX_HP
		view.hp_bg.visible = damaged
		view.hp_fill.visible = damaged
		if damaged:
			var width: int = maxi(1, int(HP_BAR_PX.x * u.hp / sim.MAX_HP))
			view.hp_fill.region_rect = Rect2(0, 0, width, HP_BAR_PX.y)


## Floating damage number: big and red for a counter hit, small and pale
## when countered.
func _on_unit_hit(target_id: int, _attacker_id: int, damage: int, strength: int) -> void:
	var view: Dictionary = _views.get(target_id, {})
	if view.is_empty():
		return
	var label := Label3D.new()
	label.text = "-%d" % damage
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 3
	label.font_size = DAMAGE_SIZES[strength]
	label.outline_size = 18
	label.outline_modulate = Color(0.3, 0.22, 0.35)
	label.modulate = DAMAGE_COLORS[strength]
	label.pixel_size = 0.03
	label.position = view.root.position + Vector3(randf_range(-1.5, 1.5), 7.5, 0)
	add_child(label)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 4.0, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


## A fallen unit shrinks and fades away.
func _on_unit_died(id: int) -> void:
	var view: Dictionary = _views.get(id, {})
	if view.is_empty():
		return
	_views.erase(id)
	_selected.erase(id)
	view.ring.visible = false
	view.hp_bg.visible = false
	view.hp_fill.visible = false
	view.sprite.play("defend")
	var tween := create_tween().set_parallel(true)
	tween.tween_property(view.sprite, "modulate:a", 0.0, 0.6)
	tween.tween_property(view.sprite, "scale", Vector3(0.6, 0.3, 1.0), 0.6)
	tween.tween_property(view.base, "scale", Vector3(0.2, 1.0, 0.2), 0.6)
	tween.chain().tween_callback(view.root.queue_free)


## Dashed lines on the ground showing where selected units are headed,
## following their planned route around obstacles.
func _draw_routes() -> void:
	_routes_mesh.clear_surfaces()
	var started := false
	var scale_factor: float = float(sim.SCALE)
	for id in _selected:
		var u: Dictionary = sim.get_unit(id)
		if u.is_empty() or not u.moving or u.path.is_empty():
			continue
		var points: Array = [Vector2(_views[id].root.position.x, _views[id].root.position.z)]
		for wp in u.path:
			points.append(Vector2(wp.x, wp.y) / scale_factor)
		if not started:
			_routes_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			started = true
		_add_dashes(points)
	if started:
		_routes_mesh.surface_end()


## Dashes every (ROUTE_DASH + ROUTE_GAP) along the whole route, measured
## from its start, so the pattern carries smoothly around corners.
func _add_dashes(points: Array) -> void:
	var y := 0.55
	var period: float = ROUTE_DASH + ROUTE_GAP
	var travelled := 0.0  # route length before this segment
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var length: float = a.distance_to(b)
		if length < 0.001:
			continue
		var dir: Vector2 = (b - a) / length
		var side: Vector2 = Vector2(-dir.y, dir.x) * ROUTE_WIDTH * 0.5
		var k: int = int(floor(travelled / period))
		while k * period < travelled + length:
			var s0: float = maxf(k * period, travelled) - travelled
			var s1: float = minf(k * period + ROUTE_DASH, travelled + length) - travelled
			if s1 > s0:
				var p0: Vector2 = a + dir * s0
				var p1: Vector2 = a + dir * s1
				var q := [p0 + side, p0 - side, p1 - side, p1 + side]
				for v in [0, 1, 2, 0, 2, 3]:
					_routes_mesh.surface_add_vertex(Vector3(q[v].x, y, q[v].y))
			k += 1
		travelled += length


## Walking units hop. A unit that stops finishes its current hop and lands.
## Purely visual (not part of the sim), so it can use frame time freely.
func _update_hops(delta: float) -> void:
	for u in sim.units:
		var view: Dictionary = _views.get(u.id, {})
		if view.is_empty():
			continue
		var phase: float = view.hop  # 0..PI = one hop; 0 = on the ground
		if u.moving or phase > 0.0:
			phase += delta * HOPS_PER_SECOND * view.hop_speed * PI
			if phase >= PI:
				# Landed. Keep hopping if still walking, otherwise stop here.
				phase = fmod(phase, PI) if u.moving else 0.0
		view.hop = phase
		var lift: float = sin(phase)  # 0 on the ground, 1 at the top
		var sprite: AnimatedSprite3D = view.sprite
		sprite.position.y = view.sprite_y + lift * HOP_HEIGHT
		# Stretch in the air, squash near the ground (only while hopping).
		var squash: float = 0.0
		if phase > 0.0:
			squash = HOP_SQUASH * (lift * 2.0 - 1.0)
		sprite.scale = Vector3(1.0 - squash * 0.5, 1.0 + squash, 1.0)
		var shrink: float = 1.0 - HOP_BASE_SHRINK * lift
		view.base.scale = Vector3(shrink, 1.0, shrink)


func _make_view(u: Dictionary) -> void:
	var root := Node3D.new()
	add_child(root)

	# Soft team-coloured base (doubles as the blob shadow).
	var base := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 3.0
	disc.bottom_radius = 3.0
	disc.height = 0.02
	disc.radial_segments = 24
	base.mesh = disc
	base.position = Vector3(0, 0.35, 0)
	var team_color: Color = TEAM_COLORS[u.team]
	base.material_override = _flat_material(Color(team_color, 0.8), true)
	root.add_child(base)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 3.3
	torus.outer_radius = 3.9
	torus.ring_segments = 12
	ring.mesh = torus
	ring.position = Vector3(0, 0.45, 0)
	ring.material_override = _flat_material(RING_COLOR, false)
	ring.visible = false
	root.add_child(ring)

	var sprite := AnimatedSprite3D.new()
	sprite.sprite_frames = _frames_by_kind[u.kind]
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = SPRITE_PIXEL_SIZE
	sprite.shaded = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Bottom of the cell on the ground (frames are drawn 2 px above it).
	sprite.position = Vector3(0, (CELL * 0.5 - 2.0) * SPRITE_PIXEL_SIZE, 0)
	root.add_child(sprite)
	# Don't let everyone bob in sync.
	sprite.play("idle")
	sprite.frame = u.id % FRAMES
	sprite.speed_scale = 0.85 + 0.3 * float((u.id * 37) % 10) / 10.0

	# HP bar (shown once damaged): dark back, team-coloured fill shrinking
	# from the right.
	var hp_bg := _hp_bar_sprite(HP_BAR_BG, true)
	var hp_fill := _hp_bar_sprite(TEAM_COLORS[u.team].lightened(0.15), false)
	hp_fill.render_priority = 2
	root.add_child(hp_bg)
	root.add_child(hp_fill)

	_views[u.id] = {
		"root": root, "ring": ring, "sprite": sprite, "base": base,
		"hp_bg": hp_bg, "hp_fill": hp_fill,
		"sprite_y": sprite.position.y,
		"hop": 0.0,  # 0 = standing on the ground
		# Slightly different hop speeds so a group drifts out of step
		# instead of bouncing in unison.
		"hop_speed": 0.88 + 0.24 * float((u.id * 53) % 11) / 10.0,
	}


func _hp_bar_sprite(color: Color, back: bool) -> Sprite3D:
	var bar := Sprite3D.new()
	bar.texture = _white
	bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bar.pixel_size = SPRITE_PIXEL_SIZE
	bar.modulate = color
	bar.shaded = false
	bar.no_depth_test = true
	bar.render_priority = 1
	bar.position = Vector3(0, HP_BAR_HEIGHT, 0)
	if back:
		bar.region_enabled = false
	else:
		# Left-anchored so it shrinks from the right.
		bar.centered = false
		bar.offset = -HP_BAR_PX * 0.5
		bar.region_enabled = true
		bar.region_rect = Rect2(Vector2.ZERO, HP_BAR_PX)
	bar.visible = false
	return bar


func _build_frames(kind: int) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for state_index in STATES.size():
		var anim: String = STATES[state_index]
		frames.add_animation(anim)
		frames.set_animation_speed(anim, STATE_FPS[anim])
		frames.set_animation_loop(anim, true)
		var row: int = kind * 3 + state_index
		for f in FRAMES:
			var region := AtlasTexture.new()
			region.atlas = ATLAS
			region.region = Rect2(f * CELL, row * CELL, CELL, CELL)
			frames.add_frame(anim, region)
	return frames


func _flat_material(color: Color, transparent: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
