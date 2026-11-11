extends Control
## Minimaps: a small map in the top-left corner of every pane, showing the
## whole island, everyone's buildings and hands as dots (in team colours),
## and an outline of the part of the map that pane is looking at. Touch or
## drag on a minimap to move that pane's camera there.
##
## Turned on and off in Settings (Settings.get_option("minimap")).

const Settings := preload("res://scripts/settings.gd")
const UI := preload("res://scripts/ui_style.gd")
const TEAM_COLORS := [Color("#ff7f9a"), Color("#6fb6ff")]
const SEA := Color("#b9e3f0")
const LAND := Color("#c3e6ad")
const SAND := Color("#f6e7c1")
const LAKE := Color("#a6d9ee")
const PLATEAU := Color("#d3ecbf")
const FOREST := Color("#9fd18a")
const RES_DOT := [Color("#9f97b8"), Color("#b98a5e"), Color("#5fc4bb")]
const VIEW := Color(1, 1, 1, 0.95)
## Size (px, before the UI scale) and its share of a small pane at most.
const SIZE := 170.0
const MAX_SHARE := 0.3
const MARGIN := 12.0

var sim: Node
var field: Node
var panes: Control
## One map per pane (pane -> control), made and dropped as panes come and go.
var _maps: Dictionary = {}


func setup(simulation: Node, the_field: Node, pane_layout: Control) -> void:
	sim = simulation
	field = the_field
	panes = pane_layout


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if panes == null:
		return
	var on: bool = Settings.get_option("minimap")
	var leaves: Array = panes._leaves() if on else []
	for leaf in _maps.keys():
		if not leaves.has(leaf):
			_maps[leaf].queue_free()
			_maps.erase(leaf)
	for leaf in leaves:
		if not _maps.has(leaf):
			_maps[leaf] = _make_map(leaf)
		var m: Control = _maps[leaf]
		var side: float = minf(SIZE * UI.ui_scale(), minf(leaf.rect.size.x, leaf.rect.size.y) * MAX_SHARE)
		m.visible = side >= 40.0
		m.position = leaf.rect.position + Vector2(MARGIN, MARGIN)
		m.size = Vector2(side, side)
		m.queue_redraw()


func _make_map(leaf) -> Control:
	var m := Control.new()
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	m.draw.connect(_draw_map.bind(m, leaf))
	m.gui_input.connect(_on_map_input.bind(m, leaf))
	add_child(m)
	panes.register_blocker(m)
	return m


## Map units (x, z) -> point on a minimap of this size.
func _to_map(ground: Vector2, side: float) -> Vector2:
	var area: Rect2 = _area()
	return (ground - area.position) / area.size * side


func _area() -> Rect2:
	var cam: Camera3D = panes._leaves()[0].camera if panes and not panes._leaves().is_empty() else null
	return cam.map_rect if cam != null else Rect2(0, 0, 820, 820)


func _draw_map(m: Control, leaf) -> void:
	if not is_instance_valid(leaf.camera) or field == null:
		return
	var side: float = m.size.x
	var box := StyleBoxFlat.new()
	box.bg_color = SEA
	box.set_corner_radius_all(roundi(side * 0.08))
	box.border_color = Color(1, 1, 1, 0.9)
	box.set_border_width_all(2)
	box.shadow_color = Color(0.2, 0.15, 0.3, 0.25)
	box.shadow_size = 4
	m.draw_style_box(box, Rect2(Vector2.ZERO, m.size))
	_poly(m, field.coastline, side, SAND, 1.04)
	_poly(m, field.coastline, side, LAND, 1.0)
	for p in field.plateaus:
		_poly(m, p, side, PLATEAU, 1.0)
	for p in field.lakes:
		_poly(m, p, side, LAKE, 1.0)
	for f in field.forests:
		m.draw_circle(_to_map(f.center, side), f.radius / _area().size.x * side, FOREST)
	if sim == null:
		return
	var dot: float = maxf(1.5, side / 110.0)
	for n in sim.nodes if "nodes" in sim else []:
		if n.res != 1 and n.amount > 0:
			m.draw_circle(_to_map(Vector2(n.x, n.z) / float(sim.SCALE), side), dot * 1.4, RES_DOT[n.res])
	for b in sim.buildings:
		var c: Vector2 = _to_map(Vector2(b.x, b.z) / float(sim.SCALE), side)
		var r: float = dot * (3.2 if b.btype == "hq" else 2.4)
		m.draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2), Color("#5f5873"))
		m.draw_rect(Rect2(c - Vector2(r, r) * 0.7, Vector2(r, r) * 1.4), TEAM_COLORS[b.team])
	for u in sim.units:
		m.draw_circle(_to_map(Vector2(u.x, u.z) / float(sim.SCALE), side), dot, TEAM_COLORS[u.team].darkened(0.15))
	# What this pane is looking at.
	var cam: Camera3D = leaf.camera
	var pane: Vector2 = leaf.rect.size
	var corners := PackedVector2Array()
	for p in [Vector2.ZERO, Vector2(pane.x, 0), pane, Vector2(0, pane.y), Vector2.ZERO]:
		var g: Vector3 = cam._ground_at_in(p, pane)
		corners.append(_to_map(Vector2(g.x, g.z), side).clamp(Vector2.ZERO, m.size))
	m.draw_polyline(corners, Color(0.3, 0.25, 0.4, 0.5), 4.0, true)
	m.draw_polyline(corners, VIEW, 2.0, true)


func _poly(m: Control, poly: PackedVector2Array, side: float, color: Color, grow: float) -> void:
	if poly.size() < 3:
		return
	var centre: Vector2 = _area().get_center()
	var pts := PackedVector2Array()
	for p in poly:
		pts.append(_to_map(centre + (p - centre) * grow, side))
	var tris: PackedInt32Array = Geometry2D.triangulate_polygon(pts)
	if tris.is_empty():
		return
	m.draw_colored_polygon(pts, color)


## Touch / drag on a minimap: that pane looks there.
func _on_map_input(event: InputEvent, m: Control, leaf) -> void:
	var at: Variant = null
	if event is InputEventScreenTouch and event.pressed:
		at = event.position
	elif event is InputEventScreenDrag:
		at = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		at = event.position
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		at = event.position
	if at == null:
		return
	look_at_map(leaf, at / m.size.x)
	m.accept_event()


## Centres a pane's camera on a point given as a share (0..1) of the map.
func look_at_map(leaf, share: Vector2) -> void:
	var area: Rect2 = _area()
	var g: Vector2 = area.position + share.clamp(Vector2.ZERO, Vector2.ONE) * area.size
	leaf.camera.target = Vector3(g.x, 0, g.y)
	leaf.camera.refit()


## The minimap of a pane (for tests), or null.
func map_of(leaf) -> Control:
	return _maps.get(leaf, null)
