class_name SunsetArena
extends Arena
## Sunset Lanes: a rooftop alley at golden hour, mid-century "googie" style.
## Three long, wide lanes with big, widely spaced pins, so a strike takes a well-aimed bowl
## (tests/strike_rate.gd: about half as many strikes as the classic alley).

const CREAM := Color("fbefd9")
const CORAL := Color("ff6f59")
const TEAL := Color("1d9a8f")
const DEEP_TEAL := Color("0f4f55")
const MUSTARD := Color("ffc145")
const BULB := Color("ffcf7a")

const SKY_SHADER := """
shader_type sky;
uniform vec3 sun_dir = vec3(-0.3, 0.035, -0.95);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 col = mix(vec3(0.95, 0.55, 0.22), vec3(0.85, 0.3, 0.32), smoothstep(0.0, 0.1, y));  // gold horizon, coral above
	col = mix(col, vec3(0.45, 0.24, 0.5), smoothstep(0.08, 0.3, y));  // mauve
	col = mix(col, vec3(0.1, 0.12, 0.34), smoothstep(0.28, 0.85, y));  // dusk blue overhead
	col = mix(col, vec3(0.36, 0.2, 0.34), smoothstep(0.0, -0.12, y));  // haze below the horizon
	float s = max(dot(d, normalize(sun_dir)), 0.0);
	col += vec3(1.0, 0.55, 0.25) * (pow(s, 6.0) * 0.4 + pow(s, 48.0) * 0.7);
	if (y > 0.0) {  // long streaky clouds, lit pink and gold toward the sun
		vec2 uv = d.xz / (y + 0.06);
		float n = noise(uv * vec2(0.35, 1.6)) * 0.65 + noise(uv * vec2(0.9, 4.0)) * 0.35;
		float c = smoothstep(0.55, 0.78, n) * smoothstep(0.01, 0.06, y) * (1.0 - smoothstep(0.3, 0.6, y));
		col = mix(col, mix(vec3(1.0, 0.56, 0.55), vec3(1.0, 0.86, 0.6), pow(s, 3.0)), c * 0.75);
	}
	col = mix(col, vec3(1.7, 1.15, 0.65), smoothstep(0.9975, 0.998, s));  // the sun, sitting on the skyline
	COLOR = col;
}
"""

const TERRAZZO_SHADER := """
shader_type spatial;
varying vec3 wp;
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	// Diamond panels split by brass strips, flecked with coloured chips.
	vec2 q = vec2(wp.x + wp.z, wp.x - wp.z) * 0.32;
	vec2 f = fract(q);
	float strip = 1.0 - smoothstep(0.0, 0.03, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
	vec3 col = mix(vec3(0.9, 0.82, 0.68), vec3(0.3, 0.66, 0.62), mod(floor(q.x) + floor(q.y), 2.0));
	vec2 g = wp.xz * 12.0;
	vec2 gc = floor(g);
	float r = h2(gc);
	vec2 o = vec2(h2(gc + 1.7), h2(gc + 4.1)) - 0.5;
	float chip = smoothstep(0.2, 0.15, length(fract(g) - 0.5 - o * 0.4) * (0.8 + r)) * step(0.5, h2(gc + 9.3));
	vec3 cc = r < 0.3 ? vec3(0.95, 0.42, 0.33) : r < 0.55 ? vec3(0.98, 0.76, 0.3) : r < 0.75 ? vec3(0.12, 0.5, 0.5) : vec3(1.0);
	col = mix(col, cc, chip * 0.85);
	ALBEDO = mix(col, vec3(0.85, 0.6, 0.25), strip);
	METALLIC = strip * 0.8;
	ROUGHNESS = 0.25;
	SPECULAR = 0.6;
}
"""

const CITY_SHADER := """
shader_type spatial;
varying vec3 wp;
varying vec3 wn;
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec2 uv = abs(wn.x) > 0.5 ? wp.zy : wp.xy;
	vec2 g = uv * vec2(0.9, 0.6);
	vec2 f = fract(g);
	float win = step(0.25, f.x) * step(f.x, 0.75) * step(0.3, f.y) * step(f.y, 0.75) * step(abs(wn.y), 0.5);
	float lit = step(0.8, h2(floor(g) + floor(wp.xz * 0.05) * 7.0));
	ALBEDO = vec3(0.12, 0.08, 0.18);
	EMISSION = vec3(1.0, 0.68, 0.32) * win * lit * 0.9;
	ROUGHNESS = 0.9;
}
"""


func _init() -> void:
	lane_count = 3
	lane_w = 4.2
	gutter_w = 0.6
	divider_w = 0.4
	lane_len = 24.0
	head_pin_z = -19.2
	pin_gap = 1.1
	pin_scale = 1.4
	pin_mass = 0.45
	aim_assist = 0.3
	screen_y = 6.5
	cam_look = Vector3(0, -5.8, -15.0)  # a little flatter: longer lanes, and the sky is the show
	style = {cap = CREAM, strip = MUSTARD, strip_glow = 0.3, deck_light = Color("ffe2b8"),
		ret = TEAL, hood = MUSTARD, hood_glow = 0.2, bench = CORAL,
		mark = Vector3(0.75, 0.16, 0.14), glow = 0.0, wood_a = Vector3(0.86, 0.6, 0.36), wood_b = Vector3(0.98, 0.8, 0.55)}


func _environment() -> void:
	var sky := Sky.new()
	sky.sky_material = _shader(SKY_SHADER)
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("f6c3ae")
	env.ambient_light_energy = 0.35
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED  # the bright sky washed out the glossy lanes
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.ssao_enabled = true
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.fog_enabled = true
	env.fog_light_color = Color("8f5a7e")
	env.fog_density = 0.0025
	env.fog_sky_affect = 0.0  # haze the city, not the sky
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	if Look.high():
		Look.dress_env(env, Color("ffd2b0"), 0.004)
		env.tonemap_exposure = 0.9  # the haze and bounce light brighten the cream floor
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()  # low golden sun from the far left, long shadows across the lanes
	sun.rotation_degrees = Vector3(-30, -115, 0)
	sun.light_color = Color("ffb36b")
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.light_volumetric_fog_energy = 0.8  # sun shafts through the palms (high graphics haze)
	add_child(sun)
	var fill := DirectionalLight3D.new()  # cool evening sky fill from behind the camera
	fill.rotation_degrees = Vector3(-45, 20, 0)
	fill.light_color = Color("b9b0ff")
	fill.light_energy = 0.35
	add_child(fill)
	for x in [-5.0, 0.0, 5.0]:
		var l := OmniLight3D.new()
		l.position = Vector3(x, 5.0, 5.5)
		l.omni_range = 11.0
		l.light_energy = 1.0
		l.light_color = Color("ffc78f")
		add_child(l)


func _floor_and_walls() -> void:
	_solid(Vector3(half_w * 2.0, 1.0, APPROACH + 10.0), Vector3(0, -0.5, APPROACH * 0.5 + 5.0), _shader(TERRAZZO_SHADER), 1.0)
	_foul_mat = Look.neon(Color("ff4a3d"), 1.6)
	Look.mesh(self, Look.box(Vector3(half_w * 2.0, 0.02, 0.12)), _foul_mat, Vector3(0, 0.005, -0.06))  # foul line
	var depth := APPROACH + lane_len + 13.0
	var mid_z := (APPROACH + 10.0 - lane_len - 3.0) * 0.5
	var cream := Look.toy(CREAM, 0.6, false)
	var coral := Look.toy(CORAL, 0.4, false)
	var deck := Look.toy(Color("a8614a"), 0.9, false)  # terracotta roof tiles
	# A waist-high parapet you can see over, plus an invisible fence above it so nobody gets thrown off the roof.
	for s in [-1.0, 1.0]:
		_invisible(Vector3(0.6, 14.0, depth), Vector3(s * (half_w + 0.3), 6.5, mid_z))
		Look.mesh(self, Look.box(Vector3(0.6, 1.1, depth)), cream, Vector3(s * (half_w + 0.3), 0.55, mid_z))
		Look.mesh(self, Look.box(Vector3(0.8, 0.14, depth)), coral, Vector3(s * (half_w + 0.3), 1.17, mid_z))
		Look.mesh(self, Look.box(Vector3(8.0, 0.4, depth + 8.0)), deck, Vector3(s * (half_w + 4.6), -0.2, mid_z - 4.0))
	_invisible(Vector3(half_w * 2.0, 14.0, 0.6), Vector3(0, 6.5, APPROACH + 0.3))  # behind the brawling floor
	Look.mesh(self, Look.box(Vector3(half_w * 2.0, 0.02, 0.15)), Look.neon(MUSTARD, 0.4), Vector3(0, 0.01, APPROACH))
	_invisible(Vector3(half_w * 2.0, 14.0, 0.6), Vector3(0, 6.5, -lane_len - 3.3))  # behind the pit
	Look.mesh(self, Look.box(Vector3(half_w * 2.0, 4.4, 0.6)), Look.toy(DEEP_TEAL, 0.8, false), Vector3(0, 0.7, -lane_len - 3.3))
	_solid(Vector3(half_w * 2.0, 1.0, 3.0), Vector3(0, PIT_Y - 0.5, -lane_len - 1.5), Look.toy(Color("0a2a30"), 1.0, false), 0.6, "pit")
	_solid(Vector3(half_w * 2.0, 0.3, 0.3), Vector3(0, -0.15, -lane_len - 0.15), cream)  # pit lip under the pin deck edge


func _decor() -> void:
	var coral := Look.toy(CORAL, 0.4, false)
	var cream := Look.toy(CREAM, 0.5, false)
	var mustard := Look.toy(MUSTARD, 0.35, false)
	var bulbs: Array[Transform3D] = []
	var wire := SurfaceTool.new()
	wire.begin(Mesh.PRIMITIVE_LINES)

	# Pinsetter canopy: coral beam, cream band, lane numbers on round badges.
	_solid(Vector3(half_w * 2.0, 1.5, 0.6), Vector3(0, 3.65, -lane_len + 0.5), coral)
	Look.mesh(self, Look.box(Vector3(half_w * 2.0, 0.24, 0.04)), cream, Vector3(0, 3.1, mask_front))
	Look.mesh(self, Look.box(Vector3(half_w * 2.0 + 0.2, 0.18, 0.8)), mustard, Vector3(0, 4.45, -lane_len + 0.5))
	var badge := CylinderMesh.new()
	badge.top_radius = 0.55
	badge.bottom_radius = 0.55
	badge.height = 0.06
	for i in lane_count:
		var b := Look.mesh(self, badge, cream, Vector3(lane_x(i), 3.75, mask_front + 0.03))
		b.rotation_degrees.x = 90.0
		_label(str(i + 1), Vector3(lane_x(i), 3.75, mask_front + 0.07), 120, TEAL, CREAM, 0.006)

	# Scoreboard in a mustard frame ringed with marquee bulbs, under the alley sign with a starburst each side.
	Look.mesh(self, Look.box(Vector3(11.8, 4.3, 0.3)), mustard, Vector3(0, screen_y, mask_front - 0.15))
	for k in 64:
		var t := k / 64.0 * 2.0 * (11.4 + 3.9)
		var p := Vector2(t - 5.7, 1.95) if t < 11.4 else Vector2(5.7, 1.95 - (t - 11.4)) if t < 15.3 \
			else Vector2(5.7 - (t - 15.3), -1.95) if t < 26.7 else Vector2(-5.7, -1.95 + (t - 26.7))
		bulbs.append(Transform3D(Basis(), Vector3(p.x, screen_y + p.y, mask_front + 0.05)))
	_label("SUNSET LANES", Vector3(0, 9.8, mask_front - 0.1), 210, CREAM, CORAL, 0.007)
	var gold := Look.neon(MUSTARD, 0.6)
	for s in [-1.0, 1.0]:
		var c := Vector3(s * 7.4, 9.8, mask_front - 0.2)
		for k in 14:
			var a := TAU * k / 14.0
			var spike := Look.mesh(self, Look.box(Vector3(0.12, 1.5 if k % 2 == 0 else 0.85, 0.06)), gold)
			spike.transform = Transform3D(Basis(Vector3.BACK, a), c).translated_local(Vector3(0, 0.6 if k % 2 == 0 else 0.4, 0))
		Look.mesh(self, Look.sphere(0.32), coral, c + Vector3(0, 0, 0.05))

	# String lights along both parapets, on posts.
	for s in [-1.0, 1.0]:
		var x: float = s * (half_w + 0.3)
		var prev := Vector3.ZERO
		for k in 7:
			var z := APPROACH - k * (APPROACH + lane_len) / 6.0
			var top := Vector3(x, 5.2, z)
			Look.mesh(self, Look.box(Vector3(0.12, 5.2, 0.12)), Look.toy(Color("3b2a3a"), 0.6, false), Vector3(x, 2.6, z))
			if k > 0:
				_strand(prev, top, 0.8, bulbs, wire)
			prev = top
	_multi(Look.sphere(0.09), Look.neon(BULB, 4.0), bulbs)
	var wm := StandardMaterial3D.new()
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wm.albedo_color = Color("2a1d2a")
	Look.mesh(self, wire.commit(), wm)

	# A giant roadside pin on the roof, palms along the parapets, and the city skyline at dusk.
	var giant := Look.mesh(self, Arena.pin_mesh(), Arena.pin_material(), Vector3(half_w + 4.8, 0.8, -16.0))
	giant.scale = Vector3.ONE * 6.0
	var plinth := CylinderMesh.new()
	plinth.top_radius = 1.3
	plinth.bottom_radius = 1.5
	plinth.height = 0.8
	Look.mesh(self, plinth, Look.toy(TEAL, 0.4), Vector3(half_w + 4.8, 0.4, -16.0))
	_palms()
	_city()


func _palms() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.13
	trunk.bottom_radius = 0.17
	trunk.height = 0.8  # taller than the gap between segments, so the trunk never shows seams
	trunk.radial_segments = 8
	var segs: Array[Transform3D] = []
	var fronds: Array[Transform3D] = []
	for s in [-1.0, 1.0]:
		for z in [9.0, 1.0, -7.0, -16.0, -24.0, -31.0]:
			if s > 0.0 and z == -16.0:
				continue  # the giant pin stands there
			var base := Vector3(s * (half_w + rng.randf_range(2.0, 3.2)), 0.0, z + rng.randf_range(-1.5, 1.5))
			var lean := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(0.8, 2.0)
			var h := rng.randf_range(5.5, 7.5)
			var top := base
			for k in 10:
				var t := (k + 0.5) / 10.0
				var p := base + Vector3.UP * h * t + lean * t * t
				var tangent := (Vector3.UP * h + lean * 2.0 * t).normalized()
				segs.append(Transform3D(Basis(Quaternion(Vector3.UP, tangent)), p))
				top = base + Vector3.UP * h + lean
			for k in 11:
				var yaw := TAU * k / 11.0 + rng.randf_range(-0.2, 0.2)
				var tilt := rng.randf_range(-0.25, 0.2) if k < 8 else rng.randf_range(0.5, 0.8)
				var sc := 1.0 if k < 8 else 0.6
				fronds.append(Transform3D(Basis.from_euler(Vector3(0, yaw, tilt)).scaled(Vector3.ONE * sc), top))
	_multi(trunk, Look.toy(Color("9a7458"), 0.85, false), segs)
	var leaf := Look.toy(Color("2f7a55"), 0.7, false)
	leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	_multi(_frond_mesh(), leaf, fronds)


func _frond_mesh() -> ArrayMesh:
	# One drooping, V-folded palm leaf along +x.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 10
	var row := []
	for k in n + 1:
		var t := float(k) / n
		var mid := Vector3(t * 2.8, 2.8 * (0.35 * t - 0.75 * t * t), 0.0)
		var w := 0.42 * sin(PI * pow(t, 0.7))
		row.append([mid + Vector3(0, -0.12 * w, -w), mid, mid + Vector3(0, -0.12 * w, w)])
	for k in n:
		for side in 2:
			var a: Vector3 = row[k][side]
			var b: Vector3 = row[k][side + 1]
			var c: Vector3 = row[k + 1][side + 1]
			var d: Vector3 = row[k + 1][side]
			for v in [a, b, c, a, c, d]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _city() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var xf: Array[Transform3D] = []
	for k in 70:
		var a := rng.randf_range(-1.9, 1.9)  # radians around the far end
		var d := rng.randf_range(110.0, 240.0)
		var top := rng.randf_range(-25.0, 0.0)  # mostly below the roof: you look out over the city
		if rng.randf() < 0.2 and absf(a + 0.3) > 0.3:
			top = rng.randf_range(8.0, 35.0)  # a few towers, never in front of the sunset
		var size := Vector3(rng.randf_range(8.0, 22.0), top + 60.0, rng.randf_range(8.0, 22.0))
		var pos := Vector3(sin(a) * d, top - size.y * 0.5, -10.0 - cos(a) * d)
		xf.append(Transform3D(Basis(Vector3.UP, -a) * Basis.from_scale(size), pos))
	_multi(Look.box(Vector3.ONE), _shader(CITY_SHADER), xf)


func _strand(a: Vector3, b: Vector3, sag: float, bulbs: Array[Transform3D], wire: SurfaceTool) -> void:
	var n := int(a.distance_to(b) / 0.6)
	var prev := a
	for k in range(1, n + 1):
		var t := float(k) / n
		var p := a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		wire.add_vertex(prev)
		wire.add_vertex(p)
		if k < n:
			bulbs.append(Transform3D(Basis(), p + Vector3.DOWN * 0.12))
		prev = p


func _multi(m: Mesh, mat: Material, xforms: Array[Transform3D]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	add_child(mi)


func _invisible(size: Vector3, pos: Vector3) -> void:
	var bs := BoxShape3D.new()
	bs.size = size
	_body(bs, pos)


func _label(text: String, pos: Vector3, font_size: int, col: Color, outline: Color, px: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = Look.title_font()
	l.font_size = font_size
	l.outline_size = int(font_size / 7.0)
	l.modulate = col
	l.outline_modulate = outline
	l.position = pos
	l.pixel_size = px
	add_child(l)


func _shader(code: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = code
	return m
