extends Control
## The economy part of the screen:
##   - resource counter (top right): stone, wood, metal; full screen button
##     under it;
##   - Build menu (bottom left): pick HQ / Quarry / Paper Mill / Forge, then
##     tap the ground to place it;
##   - building panel (beside the buildings, when your buildings are selected by
##     tap or lasso): a row per type with HP, and for factories a train
##     button (queues at the least busy one), the queue and progress;
##   - victory / defeat screen with Play Again.
## It shows things and reports button presses; game_controller.gd decides
## what they mean.

const UI := preload("res://scripts/ui_style.gd")

signal build_chosen(btype: String)  # "" = cancelled
signal train_pressed(building_id: int)
signal play_again_pressed

const FACTORIES := ["quarry", "mill", "forge"]
const FACTORY_COLORS := {"quarry": Color("#ddd6ea"), "mill": Color("#fbf1d6"), "forge": Color("#c4eeea"),
		"hq": Color("#fbe3ea")}
## Small town hall picture for the Build menu.
var HQ_ICON: Texture2D = _small_hq_icon()
const BUILD_COLOR := Color("#e7e1f5")
const BUILD_ARMED := Color("#c9bdf0")

var sim: Node
var team := 0

var resource_bar: PanelContainer
var fullscreen_button: Button
var build_menu: VBoxContainer
var building_panel: PanelContainer
var game_over_screen: Control

var _res_labels: Array = []
var _build_toggle: Button
var _build_options: Dictionary = {}  # btype -> Button
var _armed_build := ""
var _panel_rows: VBoxContainer
var _rows: Dictionary = {}        # building type -> row controls
var _train_button: Button         # first row's train button (for tests)
var _panel_buildings: Array = []  # selected building ids
var _over_label: Label
var _toast: Label
var _toast_tween: Tween


func setup(simulation: Node, player_team: int) -> void:
	sim = simulation
	team = player_team


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_resource_bar()
	_build_fullscreen_button()
	_build_build_menu()
	_build_building_panel()
	_build_game_over()
	_toast = UI.label("", 30)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.position.y = 90
	_toast.add_theme_color_override("font_outline_color", Color.WHITE)
	_toast.add_theme_constant_override("outline_size", 10)
	_toast.modulate.a = 0.0
	add_child(_toast)


## A short message near the top of the screen that fades away.
func toast(text: String) -> void:
	_toast.text = text
	_toast.reset_size()
	_toast.position.x = (size.x - _toast.size.x) * 0.5
	if _toast_tween != null:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.2)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)


func _process(_delta: float) -> void:
	if sim == null:
		return
	for res in 3:
		_res_labels[res].text = str(sim.resources[team][res])
	for btype in _build_options:
		var spec: Dictionary = sim.BUILDINGS[btype]
		_build_options[btype].disabled = not sim.can_afford(team, spec.res, spec.cost)
	_refresh_building_panel()


## The build the player picked and still has to place ("" if none).
func armed_build() -> String:
	return _armed_build


func clear_build() -> void:
	_armed_build = ""
	_build_toggle.set_pressed_no_signal(false)
	_show_build_options(false)


## Puts the building panel beside `target` (screen rect of the selected
## buildings), inside `bounds` (their pane): to the right, or to the left if
## there's no room. An empty target puts it back at the bottom centre.
func place_building_panel(target: Rect2, bounds: Rect2) -> void:
	if not target.has_area():
		building_panel.anchor_left = 0.5
		building_panel.anchor_right = 0.5
		building_panel.anchor_top = 1.0
		building_panel.anchor_bottom = 1.0
		building_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		building_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		building_panel.offset_left = 0
		building_panel.offset_right = 0
		building_panel.offset_top = 0
		building_panel.offset_bottom = -104
		return
	var size: Vector2 = building_panel.get_combined_minimum_size()
	var gap := 14.0
	var x: float = target.end.x + gap
	if x + size.x > bounds.end.x:
		x = target.position.x - gap - size.x
	var y: float = target.get_center().y - size.y * 0.5
	var screen: Vector2 = get_viewport_rect().size
	x = clampf(x, 8.0, maxf(8.0, screen.x - size.x - 8.0))
	y = clampf(y, maxf(8.0, bounds.position.y + 8.0), maxf(8.0, minf(bounds.end.y, screen.y) - size.y - 8.0))
	building_panel.anchor_left = 0.0
	building_panel.anchor_right = 0.0
	building_panel.anchor_top = 0.0
	building_panel.anchor_bottom = 0.0
	building_panel.grow_horizontal = Control.GROW_DIRECTION_END
	building_panel.grow_vertical = Control.GROW_DIRECTION_END
	building_panel.position = Vector2(x, y).round()
	building_panel.size = size


## Shows the panel for these buildings (one row per type), or hides it.
func show_buildings(ids: Array) -> void:
	_panel_buildings = ids.duplicate()
	_refresh_building_panel()


func show_game_over(winner: int) -> void:
	_over_label.text = "Victory!" if winner == team else "Defeat"
	game_over_screen.visible = true


## Controls that touches on the map should ignore.
func blockers() -> Array:
	return [resource_bar, fullscreen_button, build_menu, building_panel, game_over_screen]


# --- Building the pieces ---------------------------------------------------------

func _build_resource_bar() -> void:
	resource_bar = PanelContainer.new()
	resource_bar.add_theme_stylebox_override("panel", UI.panel_box())
	resource_bar.anchor_left = 1.0
	resource_bar.anchor_right = 1.0
	resource_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	resource_bar.offset_top = 16
	resource_bar.offset_right = -24
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	resource_bar.add_child(row)
	for res in 3:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 8)
		var icon := TextureRect.new()
		icon.texture = UI.res_icon(res)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.custom_minimum_size = Vector2(44, 44)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chip.add_child(icon)
		var l := UI.label("0", 30)
		l.custom_minimum_size = Vector2(70, 0)
		chip.add_child(l)
		row.add_child(chip)
		_res_labels.append(l)
	add_child(resource_bar)


## Full screen on / off (top right, under the resource counter). In a
## browser this hides the address bar; browsers only allow it from a tap.
func _build_fullscreen_button() -> void:
	fullscreen_button = UI.button(Color(1, 1, 1, 0.85), Color("#e7e1f5"))
	fullscreen_button.icon = UI.fullscreen_icon()
	fullscreen_button.custom_minimum_size = Vector2(72, 72)
	fullscreen_button.anchor_left = 1.0
	fullscreen_button.anchor_right = 1.0
	fullscreen_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	fullscreen_button.offset_top = 100
	fullscreen_button.offset_right = -24
	fullscreen_button.pressed.connect(toggle_fullscreen)
	# Native apps are full screen already.
	fullscreen_button.visible = not (OS.has_feature("android") or OS.has_feature("ios"))
	add_child(fullscreen_button)


func toggle_fullscreen() -> void:
	var full: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


static func _small_hq_icon() -> Texture2D:
	var img: Image = (load("res://assets/env/hq_red.png") as Texture2D).get_image()
	img.resize(int(img.get_width() * 72.0 / img.get_height()), 72, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


func _build_build_menu() -> void:
	# Options stack upwards above the Build button, clear of the panels at
	# the bottom centre.
	build_menu = VBoxContainer.new()
	build_menu.add_theme_constant_override("separation", 12)
	build_menu.alignment = BoxContainer.ALIGNMENT_END
	build_menu.anchor_top = 1.0
	build_menu.anchor_bottom = 1.0
	build_menu.grow_vertical = Control.GROW_DIRECTION_BEGIN
	build_menu.offset_left = 24
	build_menu.offset_bottom = -104
	_build_toggle = UI.button(BUILD_COLOR, BUILD_ARMED)
	_build_toggle.text = "Build"
	_build_toggle.toggle_mode = true
	_build_toggle.toggled.connect(func(on):
		if not on:
			_armed_build = ""
		_show_build_options(on)
		if not on:
			build_chosen.emit(""))
	for btype in ["hq"] + FACTORIES:
		var kind: int = FACTORIES.find(btype)
		var b := UI.button(FACTORY_COLORS[btype], FACTORY_COLORS[btype].darkened(0.15), 24)
		if btype == "hq":
			# Another HQ: 150 of every resource, anywhere on the map.
			b.icon = HQ_ICON
			b.expand_icon = false
			b.text = "%s\n150 of each" % UI.BUILDING_NAMES[btype]
		else:
			b.icon = UI.kind_icon(kind)
			b.text = "%s\n%d %s" % [UI.BUILDING_NAMES[btype], 150, UI.RES_NAMES[kind]]
		b.pressed.connect(func():
			_armed_build = btype
			_show_build_options(false)
			_build_toggle.text = "Cancel"
			build_chosen.emit(btype))
		b.visible = false
		build_menu.add_child(b)
		_build_options[btype] = b
	build_menu.add_child(_build_toggle)
	_build_toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(build_menu)


func _show_build_options(on: bool) -> void:
	for btype in _build_options:
		_build_options[btype].visible = on
	if not on and _armed_build == "":
		_build_toggle.text = "Build"
	if not on and _armed_build == "" and _build_toggle.button_pressed:
		_build_toggle.set_pressed_no_signal(false)


func _build_building_panel() -> void:
	building_panel = PanelContainer.new()
	building_panel.add_theme_stylebox_override("panel", UI.panel_box())
	building_panel.anchor_left = 0.5
	building_panel.anchor_right = 0.5
	building_panel.anchor_top = 1.0
	building_panel.anchor_bottom = 1.0
	building_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	building_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	building_panel.offset_bottom = -104
	_panel_rows = VBoxContainer.new()
	_panel_rows.add_theme_constant_override("separation", 10)
	building_panel.add_child(_panel_rows)
	building_panel.visible = false
	add_child(building_panel)


## One row of the panel: a building type with how many are selected, its
## state, and (for factories) a train button and progress bar.
func _make_row(btype: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var text := VBoxContainer.new()
	text.custom_minimum_size = Vector2(230, 0)
	var title := UI.label("", 30)
	var info := UI.label("", 22)
	text.add_child(title)
	text.add_child(info)
	row.add_child(text)
	var train := UI.button(Color("#fbe3ea"), Color("#f2c4d2"), 26)
	train.pressed.connect(func(): _on_train(btype))
	row.add_child(train)
	var progress := ProgressBar.new()
	progress.custom_minimum_size = Vector2(160, 22)
	progress.show_percentage = false
	progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#ff9fb4")
	fill.set_corner_radius_all(10)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.3, 0.27, 0.4, 0.2)
	back.set_corner_radius_all(10)
	progress.add_theme_stylebox_override("fill", fill)
	progress.add_theme_stylebox_override("background", back)
	row.add_child(progress)
	_panel_rows.add_child(row)
	return {"row": row, "title": title, "info": info, "train": train, "progress": progress}


## Selected buildings of a type that still stand.
func _standing(btype: String) -> Array:
	var out: Array = []
	for id in _panel_buildings:
		var b: Dictionary = sim.get_entity(id)
		if not b.is_empty() and b.has("btype") and b.btype == btype:
			out.append(b)
	return out


## Train at the least busy finished factory of this type in the selection.
func _on_train(btype: String) -> void:
	var spec: Dictionary = sim.BUILDINGS[btype]
	var best: Dictionary = {}
	for b in _standing(btype):
		if b.progress < spec.build or b.queue.size() >= sim.QUEUE_MAX:
			continue
		if best.is_empty() or b.queue.size() < best.queue.size():
			best = b
	if not best.is_empty():
		train_pressed.emit(best.id)


func _refresh_building_panel() -> void:
	if sim == null:
		return
	# Rows in a fixed order, one per type still standing in the selection.
	var types: Array = []
	for btype in ["hq"] + FACTORIES:
		if not _standing(btype).is_empty():
			types.append(btype)
	building_panel.visible = not types.is_empty()
	for btype in _rows.keys():
		if not types.has(btype):
			_rows[btype].row.queue_free()
			_rows.erase(btype)
	for btype in types:
		if not _rows.has(btype):
			_rows[btype] = _make_row(btype)
		_panel_rows.move_child(_rows[btype].row, types.find(btype))
		_refresh_row(btype, _rows[btype])
	_train_button = _rows[types[0]].train if not types.is_empty() else null


func _refresh_row(btype: String, r: Dictionary) -> void:
	var spec: Dictionary = sim.BUILDINGS[btype]
	var group: Array = _standing(btype)
	var hp := 0
	var max_hp := 0
	var going_up := 0
	var queued := 0
	var ready := 0
	var best_train := 0
	var best_build := 0
	for b in group:
		hp += b.hp
		max_hp += b.max_hp
		queued += b.queue.size()
		if b.progress < spec.build:
			going_up += 1
			best_build = maxi(best_build, b.progress)
		else:
			ready += 1
			if not b.queue.is_empty():
				best_train = maxi(best_train, b.train)
	var name: String = UI.BUILDING_NAMES[btype]
	r.title.text = name if group.size() == 1 else "%s  × %d" % [name, group.size()]
	var info := "HP %d / %d" % [hp, max_hp]
	if going_up > 0:
		info += "  ·  building…" if group.size() == 1 else "  ·  %d building…" % going_up
	r.info.text = info
	var factory: bool = spec.kind >= 0
	r.train.visible = factory
	r.progress.visible = factory or going_up > 0
	if ready == 0 and going_up > 0:
		r.progress.max_value = spec.build
		r.progress.value = best_build
	elif factory:
		r.progress.max_value = sim.TRAIN_TICKS
		r.progress.value = best_train
	if factory:
		r.train.icon = UI.kind_icon(spec.kind)
		var q: String = "" if queued == 0 else "  (%d queued)" % queued
		r.train.text = "+  %d %s%s" % [sim.UNIT_COST, UI.RES_NAMES[spec.res], q]
		r.train.disabled = ready == 0 or queued >= sim.QUEUE_MAX * ready \
				or not sim.can_afford(team, spec.res, sim.UNIT_COST)


func _build_game_over() -> void:
	game_over_screen = ColorRect.new()
	game_over_screen.color = Color(0.25, 0.2, 0.35, 0.45)
	game_over_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 30)
	_over_label = UI.label("", 110)
	_over_label.add_theme_color_override("font_color", Color.WHITE)
	_over_label.add_theme_color_override("font_outline_color", Color(0.35, 0.25, 0.45))
	_over_label.add_theme_constant_override("outline_size", 18)
	_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_over_label)
	var again := UI.button(Color("#fbe3ea"), Color("#f2c4d2"), 34)
	again.text = "Play again"
	again.pressed.connect(func(): play_again_pressed.emit())
	box.add_child(again)
	game_over_screen.add_child(box)
	game_over_screen.visible = false
	add_child(game_over_screen)
