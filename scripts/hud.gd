extends Control
## The economy part of the screen:
##   - resource counter (top right): stone, wood, metal;
##   - Build menu (bottom left): pick Quarry / Paper Mill / Forge, then tap
##     the ground to place it;
##   - factory panel (bottom centre, when one of your buildings is selected):
##     train units, see the queue and progress;
##   - victory / defeat screen with Play Again.
## It shows things and reports button presses; game_controller.gd decides
## what they mean.

const UI := preload("res://scripts/ui_style.gd")

signal build_chosen(btype: String)  # "" = cancelled
signal train_pressed(building_id: int)
signal play_again_pressed

const FACTORIES := ["quarry", "mill", "forge"]
const FACTORY_COLORS := {"quarry": Color("#ddd6ea"), "mill": Color("#fbf1d6"), "forge": Color("#c4eeea")}
const BUILD_COLOR := Color("#e7e1f5")
const BUILD_ARMED := Color("#c9bdf0")

var sim: Node
var team := 0

var resource_bar: PanelContainer
var build_menu: VBoxContainer
var building_panel: PanelContainer
var game_over_screen: Control

var _res_labels: Array = []
var _build_toggle: Button
var _build_options: Dictionary = {}  # btype -> Button
var _armed_build := ""
var _panel_title: Label
var _panel_info: Label
var _train_button: Button
var _progress: ProgressBar
var _panel_building := 0
var _over_label: Label


func setup(simulation: Node, player_team: int) -> void:
	sim = simulation
	team = player_team


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_resource_bar()
	_build_build_menu()
	_build_building_panel()
	_build_game_over()


func _process(_delta: float) -> void:
	if sim == null:
		return
	for res in 3:
		_res_labels[res].text = str(sim.resources[team][res])
	for btype in FACTORIES:
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


func show_building(id: int) -> void:
	_panel_building = id
	_refresh_building_panel()


func show_game_over(winner: int) -> void:
	_over_label.text = "Victory!" if winner == team else "Defeat"
	game_over_screen.visible = true


## Controls that touches on the map should ignore.
func blockers() -> Array:
	return [resource_bar, build_menu, building_panel, game_over_screen]


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
		icon.custom_minimum_size = Vector2(34, 34)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chip.add_child(icon)
		var l := UI.label("0", 30)
		l.custom_minimum_size = Vector2(70, 0)
		chip.add_child(l)
		row.add_child(chip)
		_res_labels.append(l)
	add_child(resource_bar)


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
	for kind in 3:
		var btype: String = FACTORIES[kind]
		var spec: Dictionary = {"cost": 150}
		var b := UI.button(FACTORY_COLORS[btype], FACTORY_COLORS[btype].darkened(0.15), 24)
		b.icon = UI.kind_icon(kind)
		b.text = "%s\n%d %s" % [UI.BUILDING_NAMES[btype], spec.cost, UI.RES_NAMES[kind]]
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	building_panel.add_child(row)
	var text := VBoxContainer.new()
	_panel_title = UI.label("", 30)
	_panel_info = UI.label("", 22)
	text.add_child(_panel_title)
	text.add_child(_panel_info)
	row.add_child(text)
	_train_button = UI.button(Color("#fbe3ea"), Color("#f2c4d2"), 26)
	_train_button.pressed.connect(func(): train_pressed.emit(_panel_building))
	row.add_child(_train_button)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(160, 22)
	_progress.show_percentage = false
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#ff9fb4")
	fill.set_corner_radius_all(10)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.3, 0.27, 0.4, 0.2)
	back.set_corner_radius_all(10)
	_progress.add_theme_stylebox_override("fill", fill)
	_progress.add_theme_stylebox_override("background", back)
	row.add_child(_progress)
	building_panel.visible = false
	add_child(building_panel)


func _refresh_building_panel() -> void:
	var b: Dictionary = {} if sim == null else sim.get_entity(_panel_building)
	if b.is_empty() or not b.has("btype"):
		building_panel.visible = false
		_panel_building = 0
		return
	building_panel.visible = true
	var spec: Dictionary = sim.BUILDINGS[b.btype]
	_panel_title.text = UI.BUILDING_NAMES[b.btype]
	var info := "HP %d / %d" % [b.hp, b.max_hp]
	var building_now: bool = b.progress < spec.build
	if building_now:
		info += "  ·  building…"
	_panel_info.text = info
	var factory: bool = spec.kind >= 0
	_train_button.visible = factory
	_progress.visible = factory or building_now
	if building_now:
		_progress.max_value = spec.build
		_progress.value = b.progress
	elif factory:
		_progress.max_value = sim.TRAIN_TICKS
		_progress.value = b.train
	if factory:
		_train_button.icon = UI.kind_icon(spec.kind)
		var queued: String = "" if b.queue.is_empty() else "  (%d queued)" % b.queue.size()
		_train_button.text = "+  %d %s%s" % [sim.UNIT_COST, UI.RES_NAMES[spec.res], queued]
		_train_button.disabled = building_now or b.queue.size() >= sim.QUEUE_MAX \
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
