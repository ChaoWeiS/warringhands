extends Control
## The Settings window (gear button): music volume and sound-effects volume
## (unit voices and building sounds). Saved on this device
## (user://settings.cfg) and applied to the "Music" and "SFX" audio buses.
##
## The static functions work without the window: Settings.apply_saved() at
## start-up, Settings.music_bus() / sfx_bus() for players.

signal closed

const UI := preload("res://scripts/ui_style.gd")
const FILE := "user://settings.cfg"
const DEFAULTS := {"music": 0.6, "sfx": 0.9}

var _music_slider: HSlider
var _sfx_slider: HSlider
## Called (with no arguments) to play a sample voice at the new volume.
var preview_sfx: Callable = func(): pass


## Creates the Music and SFX buses (once), then applies the saved volumes.
static func apply_saved() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	set_volume("music", get_volume("music"), false)
	set_volume("sfx", get_volume("sfx"), false)


static func music_bus() -> StringName:
	_ensure_bus("Music")
	return &"Music"


static func sfx_bus() -> StringName:
	_ensure_bus("SFX")
	return &"SFX"


## 0..1 (0 = silent).
static func get_volume(which: String) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(FILE) != OK:
		return DEFAULTS[which]
	return clampf(float(cfg.get_value("audio", which, DEFAULTS[which])), 0.0, 1.0)


static func set_volume(which: String, value: float, save: bool = true) -> void:
	var bus: int = AudioServer.get_bus_index("Music" if which == "music" else "SFX")
	if bus >= 0:
		AudioServer.set_bus_mute(bus, value <= 0.001)
		# Sliders feel even when loudness follows a curve, not a straight line.
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(value * value, 0.0001)))
	if save:
		var cfg := ConfigFile.new()
		cfg.load(FILE)
		cfg.set_value("audio", which, value)
		cfg.save(FILE)


static func _ensure_bus(name: String) -> void:
	if AudioServer.get_bus_index(name) >= 0:
		return
	AudioServer.add_bus()
	var i: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_send(i, &"Master")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.25, 0.2, 0.35, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(e):
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
			close())
	add_child(shade)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.panel_box(Color(1, 1, 1, 0.96)))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var s: float = UI.ui_scale()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", roundi(18 * s))
	panel.add_child(column)
	var title := UI.label("Settings", roundi(48 * s))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_music_slider = _slider_row(column, "Music", "music")
	_sfx_slider = _slider_row(column, "Sound effects (voices, buildings)", "sfx")
	_sfx_slider.drag_ended.connect(func(_changed): preview_sfx.call())
	var done := UI.button(Color("#e7e1f5"), Color("#d6cdef"), 30)
	done.text = "Done"
	done.custom_minimum_size.x = 220 * s
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done.pressed.connect(close)
	column.add_child(done)


func _slider_row(column: VBoxContainer, text: String, which: String) -> HSlider:
	var s: float = UI.ui_scale()
	var label := UI.label(text, roundi(28 * s))
	column.add_child(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(16 * s))
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = round(get_volume(which) * 100)
	slider.custom_minimum_size = Vector2(460, 56) * s
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# A chunky, finger-friendly slider.
	var grabber := _dot(roundi(44 * s), Color("#c9bdf0"))
	slider.add_theme_icon_override("grabber", grabber)
	slider.add_theme_icon_override("grabber_highlight", grabber)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.3, 0.27, 0.4, 0.18)
	track.set_corner_radius_all(10)
	track.content_margin_top = 8 * s
	track.content_margin_bottom = 8 * s
	slider.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#ff9fb4")
	fill.set_corner_radius_all(10)
	fill.content_margin_top = 8 * s
	fill.content_margin_bottom = 8 * s
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	var percent := UI.label("%d%%" % slider.value, roundi(26 * s))
	percent.custom_minimum_size.x = 90 * s
	slider.value_changed.connect(func(v):
		percent.text = "%d%%" % v
		set_volume(which, v / 100.0))
	row.add_child(slider)
	row.add_child(percent)
	column.add_child(row)
	return slider


func close() -> void:
	closed.emit()
	queue_free()


static func _dot(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r: float = size * 0.5
	for y in size:
		for x in size:
			var d: float = Vector2(x + 0.5 - r, y + 0.5 - r).length()
			if d <= r - 1:
				img.set_pixel(x, y, Color.WHITE if d > r - 5 else color)
	return ImageTexture.create_from_image(img)
