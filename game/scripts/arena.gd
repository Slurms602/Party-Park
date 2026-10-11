class_name Arena
extends Node3D
## The cosmic bowling alley: building geometry, pins, roll detection, scoring and re-racks (server side).

signal roll_finished(lane: int, bowler: int, knocked: int, kind: String)

const LANES := 4
const LANE_W := 2.8
const GUTTER_W := 0.55
const DIVIDER_W := 0.35
const PITCH := LANE_W + 2.0 * GUTTER_W + DIVIDER_W
const LANE_LEN := 18.0
const HEAD_PIN_Z := -14.6
const PIN_GAP := 0.78
const APPROACH := 12.0
const HALF_W := LANES * PITCH * 0.5 + DIVIDER_W * 0.5
const PIT_Y := -1.5
const MASK_FRONT := -LANE_LEN + 0.82  # front face of the panel hanging over the pin decks
const RERACK_FULL := 2.2  # seconds after all pins are down
const RERACK_PARTIAL := 12.0  # leftover pins stay up this long, so someone can go for the spare

const LANE_SHADER := """
shader_type spatial;
uniform float lane_w = 2.8;
uniform float half_len = 9.0;
varying vec3 lp;
float h(float n) { return fract(sin(n * 91.7) * 43758.5); }
void vertex() { lp = VERTEX; }
void fragment() {
	float u = clamp(lp.x / lane_w + 0.5, 0.0, 1.0);
	float d = half_len - lp.z;  // metres past the foul line
	float board = floor(u * 39.0);
	float grain = sin(d * 3.0 + h(board) * 20.0 + sin(d * 0.7 + board) * 2.0) * 0.5 + 0.5;
	vec3 wood = mix(vec3(0.78, 0.42, 0.16), vec3(0.95, 0.62, 0.30), h(board) * 0.6 + grain * 0.25);
	float seam = smoothstep(0.0, 0.04, fract(u * 39.0)) * smoothstep(1.0, 0.96, fract(u * 39.0));
	wood *= mix(0.65, 1.0, seam);
	// Target arrows (a V of seven) and approach-side dots glow under the blacklight.
	float glow = 0.0;
	for (int i = 1; i <= 7; i++) {
		float bx = float(i) * 5.0 / 39.0;
		float tip = 4.2 + abs(float(i) - 4.0) * 0.35;
		vec2 q = vec2((u - bx) * lane_w, d - tip);
		float tri = max(abs(q.x) * 3.2 + q.y, -q.y - 0.45);
		glow = max(glow, smoothstep(0.03, 0.0, tri));
	}
	vec3 neon = vec3(0.2, 0.95, 1.0);
	float edge = smoothstep(0.012, 0.0, min(u, 1.0 - u));
	ALBEDO = mix(wood, neon, glow);
	EMISSION = neon * (glow * 2.5 + edge * 1.5);
	ROUGHNESS = 0.07;
	SPECULAR = 0.7;
}
"""

const CARPET_SHADER := """
shader_type spatial;
varying vec3 wp;
float h2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec3 pal(float t) {
	vec3 c[4] = vec3[](vec3(1.0, 0.2, 0.7), vec3(0.2, 0.9, 1.0), vec3(1.0, 0.85, 0.2), vec3(0.5, 1.0, 0.3));
	return c[int(t * 4.0) % 4];
}
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz * 0.9;
	vec2 c = floor(p);
	vec2 f = fract(p) - 0.5;
	float r = h2(c);
	float a = r * 6.283;
	vec2 q = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a))) * f;
	float d;
	if (r < 0.33) d = abs(length(f - (h2(c + 3.0) - 0.5) * 0.2) - 0.22) - 0.035;
	else if (r < 0.7) d = max(abs(q.y - 0.1 * sin(q.x * 20.0)) - 0.03, abs(q.x) - 0.36);
	else d = max(abs(q.x) + q.y * 0.6 - 0.16, -q.y - 0.12);
	float m = smoothstep(0.015, -0.015, d) * step(0.35, h2(c + 11.0));
	float star = step(0.985, h2(floor(wp.xz * 9.0))) * 0.8;
	vec3 col = pal(h2(c + 7.0));
	ALBEDO = mix(vec3(0.025, 0.02, 0.07), col * 0.35, m);
	EMISSION = col * m * 0.8 + vec3(0.7, 0.8, 1.0) * star * 0.6;
	ROUGHNESS = 0.95;
}
"""

var lanes: Array[Dictionary] = []
var pins: Array[RigidBody3D] = []
var screen_board: Control  # the overhead scoreboard lives in a SubViewport
var _server := false


func setup(is_server: bool) -> void:
	_server = is_server
	_environment()
	_floor_and_walls()
	for i in LANES:
		_lane(i)
	_decor()


func lane_x(i: int) -> float:
	return (i - (LANES - 1) * 0.5) * PITCH


func lane_at(x: float) -> int:
	for i in LANES:
		if absf(x - lane_x(i)) < LANE_W * 0.5 + GUTTER_W:
			return i
	return -1


func spawn_point(i: int) -> Vector3:
	return Vector3(((i % 4) - 1.5) * 3.2, 1.2, 5.0 + (i / 4) * 2.5)


func ball_return_point(x: float) -> Vector3:
	return Vector3(PITCH * signf(x) if absf(x) > 0.01 else PITCH, 1.8, 3.2)


# ---------------------------------------------------------------- server rules

func server_update(dt: float, beasts: Array) -> void:
	for lane in lanes:
		_update_lane(lane, dt, beasts)


func _update_lane(lane: Dictionary, dt: float, beasts: Array) -> void:
	if lane.racking:
		return
	if lane.ball == null:
		for b: Beast in beasts:
			if b.is_rollable() and b.last_toucher != 0 and lane_at(b.global_position.x) == lane.i \
					and b.global_position.z < -0.3 and b.global_position.z > HEAD_PIN_Z + 1.0 \
					and b.linear_velocity.z < -2.5 and standing(lane) > 0:
				lane.ball = b
				lane.bowler = b.last_toucher
				lane.before = standing(lane)
				lane.t = 0.0
				lane.done_t = 0.0
				lane.rerack = -1.0
				break
	if lane.ball != null:
		var b = lane.ball  # untyped: the bowled player may have disconnected (freed)
		lane.t += dt
		var ball_done: bool = not is_instance_valid(b) or not b.is_rollable() \
			or b.global_position.z < -LANE_LEN or b.global_position.y < -0.6 \
			or b.linear_velocity.length() < 0.6 or lane_at(b.global_position.x) != lane.i
		if ball_done:
			lane.done_t += dt
		if (lane.done_t > 1.0 and (_settled(lane) or lane.done_t > 2.5)) or lane.t > 8.0:
			_finish_roll(lane)
		return
	if lane.rerack < 0.0 and standing(lane) < 10:
		lane.rerack = RERACK_PARTIAL
	if lane.rerack >= 0.0:
		lane.rerack -= dt
		if lane.rerack <= 0.0:
			_rerack(lane, beasts)


func _finish_roll(lane: Dictionary) -> void:
	var left := standing(lane)
	var knocked: int = lane.before - left
	var kind := ""
	if knocked == 10:
		kind = "strike"
	elif left == 0 and knocked > 0:
		kind = "spare"
	elif knocked == 0:
		kind = "gutter"
	lane.ball = null
	lane.rerack = RERACK_FULL if left == 0 else RERACK_PARTIAL
	roll_finished.emit(lane.i, lane.bowler, knocked, kind)


func standing(lane: Dictionary) -> int:
	var n := 0
	for k in 10:
		var p: RigidBody3D = lane.pins[k]
		var spot: Vector3 = lane.rack[k]
		if p.global_transform.basis.y.dot(Vector3.UP) > 0.8 and p.global_position.y > -0.2 \
				and Vector2(p.global_position.x - spot.x, p.global_position.z - spot.z).length() < 0.45:
			n += 1
	return n


func _settled(lane: Dictionary) -> bool:
	for p: RigidBody3D in lane.pins:
		if p.linear_velocity.length() > 0.3 or p.angular_velocity.length() > 1.5:
			return false
	return true


func _rerack(lane: Dictionary, beasts: Array) -> void:
	for b: Beast in beasts:
		if lane.pins.has(b.holding):
			b.release_hold()
	lane.racking = true
	var tw := create_tween().set_parallel()
	for k in 10:
		var p: RigidBody3D = lane.pins[k]
		p.freeze = true
		tw.tween_property(p, "global_transform", Transform3D(Basis(), lane.rack[k] + Vector3.UP * 3.5), 0.5)
	tw.chain().tween_interval(0.15)
	tw.chain()
	for k in 10:
		tw.tween_property(lane.pins[k], "global_transform", Transform3D(Basis(), lane.rack[k]), 0.6) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func():
		for p: RigidBody3D in lane.pins:
			p.freeze = false
			p.linear_velocity = Vector3.ZERO
			p.angular_velocity = Vector3.ZERO
		lane.racking = false
		lane.rerack = -1.0)


# ---------------------------------------------------------------- pin sync

func pin_snapshot() -> PackedByteArray:
	# Half floats keep all 40 pins (~560 bytes) inside one network packet.
	var a := PackedByteArray()
	a.resize(pins.size() * 14)
	for i in pins.size():
		var t := pins[i].global_transform
		var q := t.basis.get_rotation_quaternion()
		var v := [t.origin.x, t.origin.y, t.origin.z, q.x, q.y, q.z, q.w]
		for k in 7:
			a.encode_half(i * 14 + k * 2, v[k])
	return a


func apply_pins(a: PackedByteArray, b: PackedByteArray, w: float) -> void:
	if a.size() != pins.size() * 14 or b.size() != a.size():
		return
	for i in pins.size():
		var o := i * 14
		var pa := Vector3(a.decode_half(o), a.decode_half(o + 2), a.decode_half(o + 4))
		var pb := Vector3(b.decode_half(o), b.decode_half(o + 2), b.decode_half(o + 4))
		var qa := Quaternion(a.decode_half(o + 6), a.decode_half(o + 8), a.decode_half(o + 10), a.decode_half(o + 12)).normalized()
		var qb := Quaternion(b.decode_half(o + 6), b.decode_half(o + 8), b.decode_half(o + 10), b.decode_half(o + 12)).normalized()
		pins[i].global_transform = Transform3D(Basis(qa.slerp(qb, w)), pa.lerp(pb, w))


# ---------------------------------------------------------------- building

func _body(shape: Shape3D, pos: Vector3, friction := 0.8, group := "") -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = pos
	var cs := CollisionShape3D.new()
	cs.shape = shape
	sb.add_child(cs)
	sb.physics_material_override = PhysicsMaterial.new()
	sb.physics_material_override.friction = friction
	if group != "":
		sb.add_to_group(group)
	add_child(sb)
	return sb


func _solid(size: Vector3, pos: Vector3, mat: Material, friction := 0.8, group := "") -> StaticBody3D:
	var bs := BoxShape3D.new()
	bs.size = size
	var sb := _body(bs, pos, friction, group)
	Look.mesh(sb, Look.box(size), mat)
	return sb


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b0618")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("6a4cff")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.ssao_enabled = true
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.fog_enabled = true
	env.fog_light_color = Color("2a1450")
	env.fog_density = 0.008
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, 25, 0)
	sun.light_color = Color("c9b8ff")
	sun.light_energy = 0.55
	sun.shadow_enabled = true
	add_child(sun)
	for x in [-5.0, 0.0, 5.0]:  # warm house lights over the brawling floor
		var l := OmniLight3D.new()
		l.position = Vector3(x, 6.5, 5.5)
		l.omni_range = 13.0
		l.light_energy = 1.6
		l.light_color = Color("ffe2c4")
		l.shadow_enabled = x == 0.0
		add_child(l)


func _floor_and_walls() -> void:
	var carpet := ShaderMaterial.new()
	carpet.shader = Shader.new()
	carpet.shader.code = CARPET_SHADER
	_solid(Vector3(HALF_W * 2.0, 1.0, APPROACH + 6.0), Vector3(0, -0.5, APPROACH * 0.5 + 3.0), carpet, 1.0)
	_solid(Vector3(HALF_W * 2.0, 0.02, 0.12), Vector3(0, 0.005, -0.06), Look.neon(Color("ff2d55"), 4.0))  # foul line
	var wall := Look.toy(Color("1b0f3a"), 0.8, false)
	var depth := APPROACH + LANE_LEN + 3.0
	var mid_z := (APPROACH - LANE_LEN - 3.0) * 0.5
	for s in [-1.0, 1.0]:
		_solid(Vector3(0.6, 7.0, depth), Vector3(s * (HALF_W + 0.3), 3.0, mid_z), wall)
		Look.mesh(self, Look.box(Vector3(0.08, 0.08, depth)), Look.neon(Color("ff3fb4") if s < 0 else Color("2de2ff")),
			Vector3(s * HALF_W, 2.6, mid_z))
	# The back wall is invisible so the camera behind it can see; a low neon rail marks it.
	var back := BoxShape3D.new()
	back.size = Vector3(HALF_W * 2.0, 8.0, 0.6)
	_body(back, Vector3(0, 3.5, APPROACH + 0.3))
	Look.mesh(self, Look.box(Vector3(HALF_W * 2.0, 0.08, 0.08)), Look.neon(Color("ffe14d"), 3.0), Vector3(0, 1.1, APPROACH))
	for x in range(-8, 9, 2):
		Look.mesh(self, Look.box(Vector3(0.06, 1.1, 0.06)), wall, Vector3(x, 0.55, APPROACH))
	_solid(Vector3(HALF_W * 2.0, 7.0, 0.6), Vector3(0, 2.0, -LANE_LEN - 3.3), Look.toy(Color("07040f"), 1.0, false))
	_solid(Vector3(HALF_W * 2.0, 1.0, 3.0), Vector3(0, PIT_Y - 0.5, -LANE_LEN - 1.5), Look.toy(Color("120a22"), 1.0, false), 0.6, "pit")
	_solid(Vector3(HALF_W * 2.0, 0.3, 0.3), Vector3(0, -0.15, -LANE_LEN - 0.15), wall)  # pit lip under the pin deck edge


func _lane(i: int) -> void:
	var x := lane_x(i)
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = LANE_SHADER
	_solid(Vector3(LANE_W, 0.4, LANE_LEN), Vector3(x, -0.2, -LANE_LEN * 0.5), mat, 0.06, "oil")
	var gutter := Look.toy(Color("8c8ca6"), 0.2, false)
	gutter.metallic = 0.8
	var cap := Look.toy(Color("2a1a55"), 0.5, false)
	for s in [-1.0, 1.0]:
		_solid(Vector3(GUTTER_W, 0.2, LANE_LEN), Vector3(x + s * (LANE_W + GUTTER_W) * 0.5, -0.42, -LANE_LEN * 0.5), gutter, 0.2)
		var cx: float = x + s * (LANE_W * 0.5 + GUTTER_W + DIVIDER_W * 0.5)
		_solid(Vector3(DIVIDER_W, 0.6, LANE_LEN), Vector3(cx, -0.22, -LANE_LEN * 0.5), cap)
		Look.mesh(self, Look.box(Vector3(0.05, 0.03, LANE_LEN)), Look.neon(Color("b04dff"), 2.5), Vector3(cx, 0.09, -LANE_LEN * 0.5))
	var light := OmniLight3D.new()  # pins get a spotlight like a real pin deck
	light.position = Vector3(x, 3.0, HEAD_PIN_Z - 1.2)
	light.omni_range = 5.5
	light.light_energy = 2.2
	light.light_color = Color("fff3e0")
	add_child(light)
	var lane := {i = i, pins = [], rack = [], ball = null, bowler = 0, before = 10, t = 0.0, done_t = 0.0, rerack = -1.0, racking = false}
	var pin_mesh := _pin_mesh()
	for row in 4:
		for k in row + 1:
			var spot := Vector3(x + (k - row * 0.5) * PIN_GAP, 0.0, HEAD_PIN_Z - row * PIN_GAP * 0.866)
			lane.rack.append(spot)
			lane.pins.append(_pin(spot, pin_mesh))
	lanes.append(lane)


static var _pin_mat: StandardMaterial3D

func _pin(spot: Vector3, m: Mesh) -> RigidBody3D:
	var p := RigidBody3D.new()
	p.mass = 0.35
	p.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	p.center_of_mass = Vector3(0, 0.38, 0)
	p.physics_material_override = PhysicsMaterial.new()
	p.physics_material_override.bounce = 0.35
	p.physics_material_override.friction = 0.4
	p.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	p.freeze = not _server  # clients only draw what the host simulates
	p.add_to_group("pins")
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.17
	cyl.height = 1.2
	cs.shape = cyl
	cs.position.y = 0.6
	p.add_child(cs)
	if _pin_mat == null:
		_pin_mat = Look.toy(Color.WHITE, 0.15)
		_pin_mat.vertex_color_use_as_albedo = true
		_pin_mat.emission_enabled = true  # pins glow a little under the blacklight
		_pin_mat.emission = Color("fff6ea")
		_pin_mat.emission_energy_multiplier = 0.35
	Look.mesh(p, m, _pin_mat)
	add_child(p)
	p.global_position = spot
	pins.append(p)
	return p


static var _pin_cache: ArrayMesh

func _pin_mesh() -> ArrayMesh:
	# A lathe-turned pin: (height, radius) profile revolved, with two red neck stripes.
	if _pin_cache:
		return _pin_cache
	var prof := [[0.0, 0.0], [0.0, 0.09], [0.06, 0.13], [0.18, 0.175], [0.34, 0.19], [0.48, 0.175],
		[0.62, 0.135], [0.74, 0.09], [0.82, 0.075], [0.9, 0.08], [0.98, 0.095], [1.06, 0.1],
		[1.13, 0.085], [1.18, 0.05], [1.2, 0.0]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 20
	for r in prof.size() - 1:
		for s in seg:
			var quad := []
			for c in [[r, s], [r + 1, s], [r + 1, s + 1], [r, s + 1]]:
				var a: float = TAU * c[1] / seg
				quad.append(Vector3(cos(a) * prof[c[0]][1], prof[c[0]][0], sin(a) * prof[c[0]][1]))
			var y: float = (quad[0].y + quad[1].y) * 0.5
			st.set_color(Color("e8202a") if (y > 0.7 and y < 0.76) or (y > 0.79 and y < 0.84) else Color("fbf7ee"))
			for v in [quad[0], quad[2], quad[1], quad[0], quad[3], quad[2]]:
				st.add_vertex(v)
	st.generate_normals()
	_pin_cache = st.commit()
	return _pin_cache


func _decor() -> void:
	# Masking panel above the pin decks with the alley sign.
	_solid(Vector3(HALF_W * 2.0, 5.4, 0.4), Vector3(0, 5.3, -LANE_LEN + 0.6), Look.toy(Color("140a2e"), 0.6, false))
	var sign := Label3D.new()
	sign.text = "BOWLING YOUR FRIENDS"
	sign.font_size = 160
	sign.outline_size = 24
	sign.modulate = Color("ffe14d")
	sign.outline_modulate = Color("ff2d95")
	sign.position = Vector3(0, 7.2, MASK_FRONT)
	sign.pixel_size = 0.006
	add_child(sign)
	for i in LANES:
		var n := Label3D.new()
		n.text = str(i + 1)
		n.font_size = 140
		n.modulate = Color("2de2ff")
		n.position = Vector3(lane_x(i), 2.85, MASK_FRONT)
		n.pixel_size = 0.006
		add_child(n)

	# Ball returns between lane pairs: knocked-out bowlers pop back out of these.
	for s in [-1.0, 1.0]:
		var base := _solid(Vector3(0.9, 0.8, 2.0), Vector3(s * PITCH, 0.4, 3.2), Look.toy(Color("2a1a55"), 0.4))
		Look.mesh(base, Look.sphere(0.55, 0.7), Look.neon(Color("ff3fb4"), 0.5), Vector3(0, 0.45, 0))

	# Overhead scoreboard screen, rendered from a SubViewport.
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 520)
	vp.transparent_bg = false
	add_child(vp)
	screen_board = Scoreboard.new()
	screen_board.big = true
	screen_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(screen_board)
	var scr := QuadMesh.new()
	scr.size = Vector2(11.0, 3.5)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_texture = vp.get_texture()
	var screen := Look.mesh(self, scr, sm, Vector3(0, 5.05, MASK_FRONT + 0.05))  # mounted on the masking unit
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Look.mesh(self, Look.box(Vector3(11.3, 3.8, 0.02)), Look.neon(Color("ff3fb4"), 1.0), Vector3(0, 5.05, MASK_FRONT + 0.01))

	# Benches on the brawling floor give people something to fall over.
	for s in [-1.0, 1.0]:
		_solid(Vector3(3.2, 0.5, 0.8), Vector3(s * 5.0, 0.25, 9.6), Look.toy(Color("ff8c42"), 0.5))
