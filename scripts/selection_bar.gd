extends HBoxContainer
## Bar at the bottom of the screen showing what's selected: each unit
## type's hand icon with a count ("× 4"). Tap one to keep only that type;
## tap Attack, then the ground, to attack-move there; tap Clear to deselect.
## Hidden when nothing is selected.

signal filter_pressed(kind: int)
signal clear_pressed
## Attack mode switched on / off.
signal attack_toggled(armed: bool)

const ATLAS := preload("res://assets/units/hands.png")
const CELL := 128
## Hand picture inside an atlas cell (frames sit at the bottom of the cell).
const ICON_INSET := Rect2(8, 12, 112, 114)
## Pastel chip colours: stone, paper, metal.
const KIND_COLORS := [Color("#d8d2e6"), Color("#fbf1d6"), Color("#c4eeea")]
const CLEAR_COLOR := Color("#f3d6de")
const ATTACK_COLOR := Color("#ffc2c2")
const ATTACK_ARMED_COLOR := Color("#ff8f8f")
const TEXT_COLOR := Color("#4a4560")

var _kind_buttons: Array = []
var _attack: Button


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
		button.icon = _kind_icon(kind)
		button.add_theme_constant_override("icon_max_width", 66)
		button.add_theme_constant_override("h_separation", 8)
		button.pressed.connect(func(): filter_pressed.emit(kind))
		add_child(button)
		_kind_buttons.append(button)
	_attack = _make_button(ATTACK_COLOR, ATTACK_ARMED_COLOR)
	_attack.text = "Attack"
	_attack.toggle_mode = true
	_attack.toggled.connect(func(on): attack_toggled.emit(on))
	add_child(_attack)
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
		button.text = "× %d" % counts[kind]
		button.visible = counts[kind] > 0
		total += counts[kind]
	visible = total > 0
	if not visible:
		set_attack_armed(false)


func is_attack_armed() -> bool:
	return _attack.button_pressed


## Turns attack mode on or off (without re-announcing it).
func set_attack_armed(on: bool) -> void:
	_attack.set_pressed_no_signal(on)


## First idle frame of the unit type, cropped to the hand.
func _kind_icon(kind: int) -> AtlasTexture:
	var icon := AtlasTexture.new()
	icon.atlas = ATLAS
	var row: int = kind * 3  # idle row of this kind
	icon.region = Rect2(ICON_INSET.position + Vector2(0, row * CELL), ICON_INSET.size)
	return icon


func _make_button(color: Color, pressed_color: Color = Color.TRANSPARENT) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 84)  # width fits the content
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 30)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, TEXT_COLOR)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var box := StyleBoxFlat.new()
		var is_pressed: bool = state == "pressed" or state == "hover_pressed"
		if is_pressed and pressed_color.a > 0.0:
			box.bg_color = pressed_color
		else:
			box.bg_color = color.darkened(0.08) if is_pressed else color
		box.set_corner_radius_all(22)
		box.content_margin_left = 20
		box.content_margin_right = 24
		box.border_color = Color(1, 1, 1, 0.9)
		box.set_border_width_all(3)
		box.shadow_color = Color(0.3, 0.25, 0.4, 0.18)
		box.shadow_size = 6
		button.add_theme_stylebox_override(state, box)
	return button
