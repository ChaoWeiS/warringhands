extends HBoxContainer
## Bar at the bottom of the screen showing what's selected.
## Tap R / P / S to keep only that type; tap Clear to deselect.
## Hidden when nothing is selected.

signal filter_pressed(kind: int)
signal clear_pressed

const KIND_NAMES := ["R", "P", "S"]
## Pastel chip colours: stone, paper, metal.
const KIND_COLORS := [Color("#d8d2e6"), Color("#fbf1d6"), Color("#c4eeea")]
const CLEAR_COLOR := Color("#f3d6de")
const TEXT_COLOR := Color("#4a4560")

var _kind_buttons: Array = []


func _ready() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_bottom = -104.0  # sits above the bottom cut tab
	add_theme_constant_override("separation", 14)
	for kind in 3:
		var button := _make_button(KIND_COLORS[kind])
		button.pressed.connect(func(): filter_pressed.emit(kind))
		add_child(button)
		_kind_buttons.append(button)
	var clear := _make_button(CLEAR_COLOR)
	clear.text = "Clear"
	clear.pressed.connect(func(): clear_pressed.emit())
	add_child(clear)
	visible = false


## counts = [rocks, papers, scissors] selected.
func show_counts(counts: Array) -> void:
	var total := 0
	for kind in 3:
		var button: Button = _kind_buttons[kind]
		button.text = "%s  %d" % [KIND_NAMES[kind], counts[kind]]
		button.visible = counts[kind] > 0
		total += counts[kind]
	visible = total > 0


func _make_button(color: Color) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(128, 78)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 30)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, TEXT_COLOR)
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = color.darkened(0.08) if state == "pressed" else color
		box.set_corner_radius_all(22)
		box.border_color = Color(1, 1, 1, 0.9)
		box.set_border_width_all(3)
		box.shadow_color = Color(0.3, 0.25, 0.4, 0.18)
		box.shadow_size = 6
		button.add_theme_stylebox_override(state, box)
	return button
