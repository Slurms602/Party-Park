class_name Look
## Shared materials: shiny toy bodies with a dark ink outline.

static var _outline: StandardMaterial3D
static var _fonts := {}

const POST_SHADER := """
shader_type canvas_item;
// High graphics finishing pass: gentle filmic contrast, split toning, lens fringing, vignette and grain.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec3 shadows_tint = vec3(0.03, 0.0, 0.06);
uniform vec3 highlights_tint = vec3(0.04, 0.02, -0.02);
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	float r2 = dot(d, d);
	vec2 off = d * r2 * 0.012;
	vec3 c = vec3(texture(screen_tex, uv + off).r, texture(screen_tex, uv).g, texture(screen_tex, uv - off).b);
	c = clamp(c, 0.0, 1.0);  // the S-curve below turns negative above 1.5 (the sun went black)
	c = mix(c, c * c * (3.0 - 2.0 * c), 0.22);
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c += shadows_tint * (1.0 - lum) + highlights_tint * lum;
	c *= 1.0 - 0.38 * smoothstep(0.08, 0.5, r2);
	c += (fract(sin(dot(uv * 997.0 + fract(TIME) * 61.0, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 0.02;
	COLOR = vec4(c, 1.0);
}
"""


static func high() -> bool:
	## High graphics (Settings): haze, modelled cosmetics, props, filmic finish.
	return _graphics() == "high"


static func fast() -> bool:
	## Fast graphics (the phone default): lower 3D resolution, one shadow cascade, outlines on bodies only.
	return _graphics() == "fast"


static func _graphics() -> String:
	# Looked up at runtime so this class also compiles in headless tests.
	var prefs := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Prefs")
	return prefs.graphics if prefs else "classic"


static func no_shadow(root: Node, keep: Array = []) -> void:
	## Stop everything under root casting shadows (except `keep`): little parts and overlays don't need them,
	## and every caster is drawn again for each shadow cascade.
	for g: GeometryInstance3D in root.find_children("*", "GeometryInstance3D", true, false):
		if not keep.has(g):
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func post_layer() -> CanvasLayer:
	## The finishing pass, drawn over the 3D scene and under every UI layer.
	var layer := CanvasLayer.new()
	layer.layer = 0
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = POST_SHADER  # set before the material gets it: a canvas material won't pick up later code changes
	rect.material = ShaderMaterial.new()
	rect.material.shader = sh
	layer.add_child(rect)
	return layer


static func dof(cam: Camera3D, far: float) -> void:
	## High graphics: the far background goes softly out of focus, like a real lens.
	var a := CameraAttributesPractical.new()
	a.dof_blur_far_enabled = true
	a.dof_blur_far_distance = far
	a.dof_blur_far_transition = far * 0.6
	a.dof_blur_amount = 0.06
	cam.attributes = a


static func dress_env(env: Environment, fog: Color, density: float) -> void:
	## High graphics: bounce light, deeper contact shadows, wider bloom and light-catching haze.
	env.ssil_enabled = true
	env.ssil_intensity = 1.3
	env.ssao_intensity = 1.8
	env.ssao_power = 1.3
	for i in 7:  # a wider, softer bloom than the default three levels
		env.set_glow_level(i, [0.0, 0.5, 0.8, 1.0, 0.6, 0.3, 0.0][i])
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = density
	env.volumetric_fog_albedo = fog
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_ambient_inject = 0.0  # only real lights light the haze, so beams stand out
	env.volumetric_fog_sky_affect = 0.0


static func font(bold := false) -> Font:
	## Fredoka: round and friendly, for body text.
	var key := "bold" if bold else "regular"
	if not _fonts.has(key):
		var v := FontVariation.new()
		v.base_font = load("res://assets/fonts/Fredoka.ttf")
		v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700 if bold else 500}
		_fonts[key] = v
	return _fonts[key]


static func title_font() -> Font:
	## Lilita One: chunky display type for titles and callouts.
	if not _fonts.has("title"):
		_fonts.title = load("res://assets/fonts/LilitaOne-Regular.ttf")
	return _fonts.title


static func outline() -> StandardMaterial3D:
	if _outline == null:
		_outline = StandardMaterial3D.new()
		_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline.cull_mode = BaseMaterial3D.CULL_FRONT
		_outline.grow = true
		_outline.grow_amount = 0.025
		_outline.albedo_color = Color(0.04, 0.02, 0.08)
	return _outline


static func toy(color: Color, roughness := 0.35, with_outline := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.3
	if high():  # a lacquered vinyl-toy coat
		m.clearcoat_enabled = true
		m.clearcoat = 0.5
		m.clearcoat_roughness = 0.15
	if with_outline and not fast():  # each outline is a second draw; on Fast only the bodies keep theirs
		m.next_pass = outline()
	return m


static func neon(color: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func mesh(parent: Node, m: Mesh, mat: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func sphere(r: float, h := -1.0) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0 if h < 0.0 else h
	s.radial_segments = 24
	s.rings = 12
	return s
