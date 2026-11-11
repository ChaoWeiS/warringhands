extends VBoxContainer
## What's selected, in a column on the right (placed by the HUD, level with
## Build): each unit type's hand icon with a count ("× 4"). Tap one to keep
## only that type. Attack (sword; then tap the ground: attack-move) and
## Hold (open palm on a stop sign: stop and stay put) are in `actions`, a
## small stack the HUD places on the left under Build. (Unselecting is a
## two-finger tap.)
## Both are hidden when nothing is selected.

signal filter_pressed(kind: int)
signal hold_pressed
## Attack mode switched on / off.
signal attack_toggled(armed: bool)

const UI := preload("res://scripts/ui_style.gd")
## Pastel chip colours: stone, paper, metal.
const KIND_COLORS := [Color("#d8d2e6"), Color("#fbf1d6"), Color("#c4eeea")]
const TEXT_COLOR := Color("#4a4560")

var _kind_buttons: Array = []
var _attack: Button
## Attack and Hold, stacked (placed on screen by the HUD).
var actions := VBoxContainer.new()


func _ready() -> void:
	add_theme_constant_override("separation", roundi(12 * UI.ui_scale()))
	for kind in 3:
		var button := _make_button(KIND_COLORS[kind])
		button.icon = _kind_icon(kind)
		button.add_theme_constant_override("icon_max_width", roundi(66 * UI.ui_scale()))
		button.add_theme_constant_override("h_separation", 8)
		button.pressed.connect(func(): filter_pressed.emit(kind))
		add_child(button)
		_kind_buttons.append(button)
	actions.add_theme_constant_override("separation", roundi(12 * UI.ui_scale()))
	_attack = UI.icon_button("attack")
	_attack.tooltip_text = "Attack"
	_attack.toggle_mode = true
	_attack.toggled.connect(func(on): attack_toggled.emit(on))
	actions.add_child(_attack)
	var hold := UI.icon_button("hold")
	hold.tooltip_text = "Hold"
	hold.pressed.connect(func(): hold_pressed.emit())
	actions.add_child(hold)
	add_sibling.call_deferred(actions)
	visible = false
	actions.visible = false


## counts = [rocks, papers, scissors] selected.
func show_counts(counts: Array) -> void:
	var total := 0
	for kind in 3:
		var button: Button = _kind_buttons[kind]
		button.text = "× %d" % counts[kind]
		button.visible = counts[kind] > 0
		total += counts[kind]
	visible = total > 0
	actions.visible = visible
	if not visible:
		set_attack_armed(false)


func is_attack_armed() -> bool:
	return _attack.button_pressed


## Turns attack mode on or off (without re-announcing it).
func set_attack_armed(on: bool) -> void:
	_attack.set_pressed_no_signal(on)
	_attack.pivot_offset = _attack.size * 0.5
	_attack.scale = Vector2.ONE * (1.12 if on else 1.0)


## First idle frame of the unit type, cropped to the hand.
func _kind_icon(kind: int) -> AtlasTexture:
	return UI.kind_icon(kind)


func _make_button(color: Color, pressed_color: Color = Color.TRANSPARENT) -> Button:
	var button := Button.new()
	var s: float = UI.ui_scale()
	button.custom_minimum_size = Vector2(0, roundf(84 * s))  # width fits the content
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", roundi(30 * s))
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
