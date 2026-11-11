extends RefCounted
## One soft shadow look for everything standing on the ground (trees,
## resource spots, buildings): a flat oval, darkest in the middle and fading
## out at the edge, nudged a little towards the bottom right (away from the
## light). Real-time shadows are off (see field.gd), so these stand in.

const COLOR := Color(0.16, 0.22, 0.2)
## Above every flat ground layer (they top out at 0.42), under buildings'
## team patches (0.5) and unit circles (0.6).
const Y := 0.46
static var _materials := {}  # strength -> material


## A shadow `radius` map units across (x), `squash` as deep (z).
static func make(radius: float, strength: float = 0.45, squash: float = 0.8) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0 * squash)
	m.mesh = plane
	m.material_override = _shared(strength)
	m.position = Vector3(radius * 0.12, Y, radius * 0.1)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


static func _shared(strength: float) -> StandardMaterial3D:
	var key: int = roundi(strength * 20)
	if not _materials.has(key):
		var grad := Gradient.new()
		grad.set_color(0, Color(COLOR, 1.0))
		grad.set_color(1, Color(COLOR, 0.0))
		grad.add_point(0.55, Color(COLOR, 0.6))
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 128
		tex.height = 128
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.albedo_color = Color(1, 1, 1, key / 20.0)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_materials[key] = mat
	return _materials[key]
