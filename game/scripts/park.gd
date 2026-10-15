class_name Park
extends Node3D
## Party Park, the world under the board: an island of sports venues with a mountain range behind it. All of it is
## built in code from the map in Party: the ground is sculpted round the paths (flattened under the venues, cut into
## the mountain along the trail), then come the paths and spaces, the venues (venues.gd), the greenery and the sky.
## The board asks it where things are (ground, spot) and has its venues play the events.

const SEA := -0.6
const ORIGIN := Vector2(-150, -175)  # the terrain's north-west corner
const SIZE := Vector2(300, 280)
const PATH_W := 2.4
## [x, z, radius x, radius z, height]: the mountains to the north, the golf course's rolls (and its pond)
const BUMPS := [
	[-8.0, -66.0, 26.0, 22.0, 34.0], [-55.0, -88.0, 44.0, 28.0, 36.0], [44.0, -100.0, 50.0, 30.0, 40.0],
	[100.0, -84.0, 38.0, 32.0, 26.0], [-104.0, -70.0, 34.0, 36.0, 22.0], [0.0, -128.0, 90.0, 34.0, 50.0],
	[-34.0, -112.0, 44.0, 28.0, 40.0], [78.0, -122.0, 50.0, 32.0, 44.0],
	[48.0, 20.0, 7.0, 6.0, 1.6], [60.0, 8.0, 6.0, 9.0, 1.4], [43.0, 3.0, 5.5, 4.5, -3.4], [66.0, 28.0, 8.0, 6.0, 1.2],
]
## [center, half size, corner radius, blend]: level ground for the venues
const PADS := [
	[Vector2(0, -1), Vector2(28, 22), 11.0, 7.0], [Vector2(0, 36), Vector2(22, 12), 10.0, 6.0],
	[Vector2(48, -40), Vector2(29, 17), 15.0, 9.0], [Vector2(-37, 21), Vector2(17, 17), 12.0, 6.0],
	[Vector2(24, 27), Vector2(12, 8), 3.0, 4.0], [Vector2(66, -13), Vector2(6, 6), 2.0, 4.0],
	[Vector2(-58, -25), Vector2(9, 7), 2.0, 4.0], [Vector2(-7, -55), Vector2(7, 4), 4.0, 6.0],
]
const PLATEAU := 0.35  # the island's flat ground, above the sea

static var _icons := {}  # space kind -> its painted face (shared by every board)
static var _cache := {}  # cell size -> what's slow to work out and never changes: the ground, paths, greenery

var cell := 1.25
var nx := 0
var nz := 0
var _h := PackedFloat32Array()
var _road := PackedFloat32Array()  # distance to the nearest path (capped at 8 m): keeps trees and props off it
var _noise := FastNoiseLite.new()
var _taken: Array = []  # [Vector2 centre, radius]: the venues' footprints
var space_y := PackedFloat32Array()  # each space's height
var trophy: Node3D
var venues := {}  # name -> its node (venues.gd): the board calls their event hooks
var tex_noise: NoiseTexture2D  # shared by the ground, the water and the sky
var _sun: DirectionalLight3D


func _ready() -> void:
	cell = 2.0 if Look.fast() else 1.25
	_noise.seed = 11
	_noise.frequency = 0.018
	_noise.fractal_octaves = 3
	tex_noise = NoiseTexture2D.new()
	tex_noise.seamless = true
	tex_noise.width = 256
	tex_noise.height = 256
	tex_noise.generate_mipmaps = true
	var nn := FastNoiseLite.new()
	nn.frequency = 0.012
	nn.fractal_octaves = 4
	tex_noise.noise = nn
	_environment()
	var c: Dictionary = _cache.get(cell, {})
	if c.is_empty():  # the first board this session: work it all out (the board is rebuilt after every minigame)
		_sculpt()
		c = {h = _h, road = _road, space_y = space_y, nx = nx, nz = nz}
		_cache[cell] = c
	else:
		_h = c.h
		_road = c.road
		space_y = c.space_y
		nx = c.nx
		nz = c.nz
	_ground_mesh(c)
	_water(c)
	_paths(c)
	_spaces()
	_trophy()
	Venues.build(self)
	_greenery(c)


# ---------------------------------------------------------------- where things are

func ground(x: float, z: float) -> float:
	## The ground's height here (bilinear in the terrain grid).
	var fx := clampf((x - ORIGIN.x) / cell, 0.0, nx - 1.001)
	var fz := clampf((z - ORIGIN.y) / cell, 0.0, nz - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := lerpf(_h[iz * nx + ix], _h[iz * nx + ix + 1], tx)
	var b := lerpf(_h[(iz + 1) * nx + ix], _h[(iz + 1) * nx + ix + 1], tx)
	return lerpf(a, b, tz)


func on_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, ground(p.x, p.z), p.z)


func spot(i: int) -> Vector3:
	## Where a space's top is.
	return Vector3(Party.SPACES[i][1], space_y[i] + 0.2, Party.SPACES[i][2])


func road(x: float, z: float) -> float:
	## How far it is to the nearest path (up to 8 m).
	var ix := clampi(roundi((x - ORIGIN.x) / cell), 0, nx - 1)
	var iz := clampi(roundi((z - ORIGIN.y) / cell), 0, nz - 1)
	return _road[iz * nx + ix]


func take(at: Vector2, radius: float) -> void:
	## A venue claims this ground: no trees or scattered props on it.
	_taken.append([at, radius])


func free_at(x: float, z: float, room := 0.0) -> bool:
	if road(x, z) < 3.0 + room or ground(x, z) < SEA + 0.6:
		return false
	for t in _taken:
		if Vector2(x, z).distance_to(t[0]) < t[1] + room:
			return false
	return true


# ---------------------------------------------------------------- sky, sun and air

const SKY_SHADER := """
shader_type sky;
// A bright, painterly day: a deep blue overhead fading to a hazy horizon, soft cumulus, and the sun.
uniform vec3 top_color = vec3(0.16, 0.45, 0.90);
uniform vec3 horizon_color = vec3(0.72, 0.87, 0.98);
uniform vec3 below_color = vec3(0.32, 0.60, 0.82);
uniform sampler2D clouds : filter_linear_mipmap, repeat_enable;
void sky() {
	vec3 d = EYEDIR;
	vec3 c = mix(horizon_color, top_color, pow(smoothstep(-0.02, 0.65, d.y), 0.65));
	c = mix(c, below_color, smoothstep(0.0, -0.25, d.y));
	float sun = max(dot(d, LIGHT0_DIRECTION), 0.0);
	c += LIGHT0_COLOR * (pow(sun, 1400.0) * 8.0 + pow(sun, 40.0) * 0.18 + pow(sun, 6.0) * 0.08);
	if (!AT_CUBEMAP_PASS && d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.08) * 0.11 + vec2(0.31, 0.17);
		float n = texture(clouds, uv).r * 0.62 + texture(clouds, uv * 2.9 + 0.37).r * 0.38;
		float cover = smoothstep(0.5, 0.68, n) * smoothstep(0.0, 0.12, d.y);
		vec3 lit = mix(vec3(0.80, 0.85, 0.95), vec3(1.0, 0.99, 0.97), smoothstep(0.55, 0.8, n));
		lit += LIGHT0_COLOR * pow(sun, 8.0) * 0.25;
		c = mix(c, lit, cover * 0.92);
	}
	COLOR = c;
}
"""


func _environment() -> void:
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = SKY_SHADER
	sm.set_shader_parameter("clouds", tex_noise)
	var sky := Sky.new()
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.ambient_light_sky_contribution = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.tonemap_white = 2.5
	env.glow_enabled = not Look.fast()
	env.glow_intensity = 0.25
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color("bcd8f2")
	env.fog_density = 0.6
	env.fog_depth_begin = 220.0
	env.fog_depth_end = 900.0
	env.fog_depth_curve = 1.6
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.1
	if not Look.fast():
		env.ssao_enabled = true
		env.ssao_radius = 1.6
		env.ssao_intensity = 1.4
		env.ssao_power = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-50, -38, 0)
	_sun.light_energy = 1.5
	_sun.light_color = Color("fff1dc")
	_sun.shadow_enabled = true
	_sun.shadow_blur = 1.5
	_sun.directional_shadow_max_distance = 80.0 if Look.fast() else 130.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if Look.fast() else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_blend_splits = true
	add_child(_sun)


# ---------------------------------------------------------------- the ground

func _raw(x: float, z: float) -> float:
	## The island before anything is built on it.
	var a := atan2(z + 8.0, x)
	var wob := 1.0 + 0.05 * sin(a * 3.0 + 0.7) + 0.03 * sin(a * 7.0 + 2.0) + 0.015 * sin(a * 13.0 + 0.3)
	var r := _coast(x, z) / wob
	var h := PLATEAU - smoothstep(0.86, 1.06, r) * 5.0
	h += _noise.get_noise_2d(x, z) * 0.7 * (1.0 - smoothstep(0.8, 0.95, r))
	for b in BUMPS:
		var dx: float = (x - b[0]) / b[2]
		var dz: float = (z - b[1]) / b[3]
		h += b[4] * exp(-(dx * dx + dz * dz))
	if z < -60.0:  # craggy peaks
		h += absf(_noise.get_noise_2d(x * 2.3, z * 2.3)) * 5.0 * smoothstep(-60.0, -100.0, z)
	return lerpf(h, minf(h, PLATEAU - smoothstep(0.93, 1.06, r) * 5.0), smoothstep(0.85, 1.0, r))  # mountains fall to the sea


func _coast(x: float, z: float) -> float:
	## How far out towards the sea (1 at the shore): the park's oval, and the mountains' bigger one to the north.
	var park := Vector2(x / 90.0, (z + 8.0) / 66.0).length()
	var hills := Vector2(x / 128.0, (z + 98.0) / 70.0).length()
	return minf(park, hills)


static func _pad_sdf(p: Vector2, c: Vector2, half: Vector2, r: float) -> float:
	var q := (p - c).abs() - half + Vector2(r, r)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r


func _sculpt() -> void:
	nx = int(SIZE.x / cell) + 1
	nz = int(SIZE.y / cell) + 1
	_h.resize(nx * nz)
	_road.resize(nx * nz)
	_road.fill(8.0)
	var levels := PADS.map(func(pad): return PLATEAU if pad[0].y > -50.0 else _raw(pad[0].x, pad[0].y))  # up the mountain: its own
	for iz in nz:
		for ix in nx:
			var x := ORIGIN.x + ix * cell
			var z := ORIGIN.y + iz * cell
			var h := _raw(x, z)
			for k in PADS.size():
				var pad: Array = PADS[k]
				var w := 1.0 - smoothstep(0.0, pad[3], _pad_sdf(Vector2(x, z), pad[0], pad[1], pad[2]))
				if w > 0.0:
					h = lerpf(h, levels[k], w)
			_h[iz * nx + ix] = h
	# The paths: each space settles at its spot's height, smoothed along the way, then the ground is cut and filled
	# to carry the path with gentle shoulders.
	var n := Party.SPACES.size()
	space_y.resize(n)
	for i in n:
		space_y[i] = maxf(ground(Party.SPACES[i][1], Party.SPACES[i][2]), PLATEAU)
	for _it in 4:
		var next := space_y.duplicate()
		for i in n:
			if Party.LIFT.has(i):
				continue
			var sum := space_y[i] * 2.0
			var k := 2.0
			for j in Party.next_spaces(i) + [Party.before(i)]:
				if not Party.LIFT.has(j):
					sum += space_y[j]
					k += 1.0
			next[i] = sum / k
		space_y = next
	var pw := PackedFloat32Array()
	pw.resize(nx * nz)
	var ph := PackedFloat32Array()
	ph.resize(nx * nz)
	for edge in edges():
		for p: Vector3 in edge:
			var cx := roundi((p.x - ORIGIN.x) / cell)
			var cz := roundi((p.z - ORIGIN.y) / cell)
			var reach := ceili(8.0 / cell)
			for iz in range(maxi(cz - reach, 0), mini(cz + reach + 1, nz)):
				for ix in range(maxi(cx - reach, 0), mini(cx + reach + 1, nx)):
					var d := Vector2(ORIGIN.x + ix * cell - p.x, ORIGIN.y + iz * cell - p.z).length()
					var k := iz * nx + ix
					_road[k] = minf(_road[k], d)
					var w := 1.0 - smoothstep(PATH_W * 0.5 + 0.6, 4.5, d)
					if w > pw[k]:
						pw[k] = w
						ph[k] = p.y - 0.06
	for k in _h.size():
		_h[k] = lerpf(_h[k], ph[k], pw[k])


func edges() -> Array:
	## The path between each pair of linked spaces, as points along a smooth curve (on the ground, ~0.5 m apart).
	## The chairlift's cable isn't a path.
	var out := []
	for i in Party.SPACES.size():
		for j in Party.next_spaces(i):
			if Party.LIFT.has(i) and Party.LIFT.has(j):
				continue
			var a := Vector3(Party.SPACES[i][1], space_y[i], Party.SPACES[i][2])
			var b := Vector3(Party.SPACES[j][1], space_y[j], Party.SPACES[j][2])
			var p0 := a
			var pb := Party.before(i)
			if Party.next_spaces(pb).has(i) and not Party.LIFT.has(pb) and Party.next_spaces(i).size() == 1:
				p0 = Vector3(Party.SPACES[pb][1], space_y[pb], Party.SPACES[pb][2])
			var nj: int = Party.next_spaces(j)[0]
			var p3 := Vector3(Party.SPACES[nj][1], space_y[nj], Party.SPACES[nj][2]) if not Party.LIFT.has(nj) and Party.next_spaces(j).size() == 1 else b
			var steps := maxi(int(a.distance_to(b) / 0.5), 2)
			var pts := []
			for s in steps + 1:
				var t := float(s) / steps
				var p := 0.5 * (2.0 * a + (b - p0) * t + (2.0 * p0 - 5.0 * a + 4.0 * b - p3) * t * t + (3.0 * a - p0 - 3.0 * b + p3) * t * t * t)
				p.y = lerpf(a.y, b.y, smoothstep(0.0, 1.0, t))
				pts.append(p)
			out.append(pts)
	return out


const GROUND_SHADER := """
shader_type spatial;
render_mode diffuse_burley;
// Painted ground: lush grass with sunny patches and darker tufts, worn dirt by the paths, sand, rock and snow
// (weights in the vertex colour: r sand, g dirt, b snow, a rock).
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
varying vec3 wpos;
varying vec3 wnrm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = NORMAL;
}
void fragment() {
	float n1 = texture(noise, wpos.xz * 0.006).r;
	float n2 = texture(noise, wpos.xz * 0.045).r;
	float n3 = texture(noise, wpos.xz * 0.21).r;
	float n4 = texture(noise, wpos.xz * 0.9).r;
	vec3 grass = mix(vec3(0.17, 0.42, 0.10), vec3(0.31, 0.55, 0.13), smoothstep(0.3, 0.7, n1));
	grass = mix(grass, vec3(0.45, 0.60, 0.17), smoothstep(0.6, 0.78, n2) * 0.4);
	grass *= 0.86 + 0.22 * n3;
	grass *= 0.94 + 0.12 * n4;
	vec3 sand = mix(vec3(0.82, 0.71, 0.50), vec3(0.74, 0.61, 0.41), n3) * (0.95 + 0.08 * n4);
	vec3 dirt = mix(vec3(0.66, 0.50, 0.32), vec3(0.52, 0.38, 0.24), n3) * (0.9 + 0.15 * n4);
	vec3 snow = mix(vec3(0.86, 0.91, 1.0), vec3(1.0), n2);
	vec2 side = mix(wpos.xy, wpos.zy, abs(wnrm.x));  // rock faces are steep: look at them side-on
	float r1 = texture(noise, side * 0.05).r;
	float r2 = texture(noise, side * vec2(0.3, 0.9)).r;
	vec3 rock = mix(vec3(0.40, 0.38, 0.37), vec3(0.58, 0.55, 0.51), smoothstep(0.35, 0.65, r1)) * (0.75 + 0.35 * r2);
	float wob = (n3 - 0.5) * 0.5;
	vec3 c = grass;
	c = mix(c, dirt, smoothstep(0.25, 0.75, COLOR.g + wob));
	c = mix(c, sand, smoothstep(0.3, 0.7, COLOR.r + wob));
	c = mix(c, rock, smoothstep(0.3, 0.7, COLOR.a + wob));
	c = mix(c, snow, smoothstep(0.35, 0.65, COLOR.b + wob));
	c *= mix(1.0, 0.78, smoothstep(0.5, -0.4, wpos.y));  // wet near the water line
	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.6, COLOR.b);
	SPECULAR = 0.2;
}
"""


func _ground_mesh(c: Dictionary) -> void:
	if not c.has("ground"):
		c.ground = _ground_arrays()
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = GROUND_SHADER
	mat.set_shader_parameter("noise", tex_noise)
	var mi := Look.mesh(self, c.ground, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _ground_arrays() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(nx * nz)
	norms.resize(nx * nz)
	cols.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			var k := iz * nx + ix
			var x := ORIGIN.x + ix * cell
			var z := ORIGIN.y + iz * cell
			var h := _h[k]
			var hl := _h[k - 1] if ix > 0 else h
			var hr := _h[k + 1] if ix < nx - 1 else h
			var hu := _h[k - nx] if iz > 0 else h
			var hd := _h[k + nx] if iz < nz - 1 else h
			var nrm := Vector3(hl - hr, 2.0 * cell, hu - hd).normalized()
			verts[k] = Vector3(x, h, z)
			norms[k] = nrm
			var slope := 1.0 - nrm.y
			var sand := smoothstep(0.8, 0.88, _coast(x, z)) * (1.0 - smoothstep(1.2, 2.5, h))
			var dirt := (1.0 - smoothstep(PATH_W * 0.5 + 0.2, 3.6, _road[k])) * 0.85
			var snow := smoothstep(27.0, 34.0, h + _noise.get_noise_2d(x * 3.0, z * 3.0) * 5.0) * (1.0 - smoothstep(0.5, 0.75, slope))
			var rock := smoothstep(0.36, 0.56, slope) * (1.0 - dirt)
			cols[k] = Color(sand, dirt, snow, rock)
	var idx := PackedInt32Array()
	idx.resize((nx - 1) * (nz - 1) * 6)
	var w := 0
	for iz in nz - 1:
		for ix in nx - 1:
			var k := iz * nx + ix
			idx[w] = k
			idx[w + 1] = k + 1
			idx[w + 2] = k + nx
			idx[w + 3] = k + 1
			idx[w + 4] = k + nx + 1
			idx[w + 5] = k + nx
			w += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


# ---------------------------------------------------------------- the sea

const WATER_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// The sea: turquoise over the sand, deep blue further out, foam where it meets the shore and gentle swell.
// The ground's height comes from a texture (r: -6..4 m), so it works the same on every renderer.
uniform sampler2D heights : filter_linear;
uniform vec4 bounds;
uniform float level;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wpos.x * 0.13 + TIME * 1.1) * 0.05 + cos(wpos.z * 0.11 + TIME * 0.9) * 0.05;
}
void fragment() {
	vec2 uv = (wpos.xz - bounds.xy) / bounds.zw;
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	float ground = mix(-6.0, texture(heights, clamp(uv, 0.0, 1.0)).r * 10.0 - 6.0, inside);
	float depth = level - ground;
	float n = texture(noise, wpos.xz * 0.05 + vec2(TIME * 0.01, TIME * 0.007)).r;
	float m = texture(noise, wpos.xz * 0.11 - vec2(TIME * 0.013, -TIME * 0.009)).r;
	vec3 shallow = vec3(0.30, 0.86, 0.82);
	vec3 deep = vec3(0.04, 0.33, 0.62);
	vec3 c = mix(shallow, deep, smoothstep(0.1, 4.5, depth + (n - 0.5) * 0.8));
	float foam = 1.0 - smoothstep(0.0, 0.35 + n * 0.25, depth);
	float lines = smoothstep(0.86, 1.0, sin((depth * 3.2 - TIME * 1.4) + n * 4.0) * 0.5 + 0.5) * (1.0 - smoothstep(0.2, 1.4, depth));
	c = mix(c, vec3(0.97, 0.99, 1.0), clamp(foam + lines * 0.6 * step(0.05, m), 0.0, 1.0));
	ALBEDO = c;
	NORMAL_MAP = normalize(vec3((n - 0.5) * 0.9, (m - 0.5) * 0.9, 1.0)) * 0.5 + 0.5;
	ROUGHNESS = 0.06 + foam * 0.6;
	SPECULAR = 0.7;
	ALPHA = clamp(depth * 2.5 + 0.35, 0.0, 1.0);
}
"""


func _water(c: Dictionary) -> void:
	if not c.has("depths"):
		var img := Image.create(nx, nz, false, Image.FORMAT_L8)
		for iz in nz:
			for ix in nx:
				var v := clampf((_h[iz * nx + ix] + 6.0) / 10.0, 0.0, 1.0)
				img.set_pixel(ix, iz, Color(v, v, v))
		c.depths = ImageTexture.create_from_image(img)
	var sea := PlaneMesh.new()
	sea.size = Vector2(1400, 1400)
	sea.subdivide_width = 70 if Look.fast() else 140
	sea.subdivide_depth = 70 if Look.fast() else 140
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = WATER_SHADER
	mat.set_shader_parameter("heights", c.depths)
	mat.set_shader_parameter("bounds", Vector4(ORIGIN.x, ORIGIN.y, (nx - 1) * cell, (nz - 1) * cell))
	mat.set_shader_parameter("level", SEA)
	mat.set_shader_parameter("noise", tex_noise)
	var mi := Look.mesh(self, sea, mat, Vector3(0, SEA, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------- paths and spaces

const PATH_SHADER := """
shader_type spatial;
// Warm paving stones in staggered rows, with a darker kerb along each edge.
uniform vec3 stone = vec3(0.92, 0.82, 0.62);
uniform vec3 kerb = vec3(0.70, 0.56, 0.40);
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 g = vec2(UV.x * 3.0, UV.y * 1.25);
	float row = floor(g.y);
	g.x += mod(row, 2.0) * 0.5;
	vec2 id = floor(g);
	vec2 f = fract(g);
	float mortar = smoothstep(0.0, 0.06, f.x) * smoothstep(1.0, 0.94, f.x) * smoothstep(0.0, 0.08, f.y) * smoothstep(1.0, 0.92, f.y);
	float n = texture(noise, UV * vec2(0.4, 0.15)).r;
	vec3 c = stone * (0.88 + 0.16 * hash(id) + 0.1 * (n - 0.5));
	c = mix(c * 0.62, c, mortar);
	float edge = smoothstep(0.1, 0.13, UV.x) * smoothstep(0.9, 0.87, UV.x);
	c = mix(kerb * (0.9 + 0.2 * n), c, edge);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
}
"""


func _paths(c: Dictionary) -> void:
	if not c.has("paths"):
		c.paths = _strips(edges())
	var mesh: ArrayMesh = c.paths
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = PATH_SHADER
	mat.set_shader_parameter("noise", tex_noise)
	var mi := Look.mesh(self, mesh, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _strips(all: Array) -> ArrayMesh:
	## One ribbon per path, PATH_W wide, laid on the ground.
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for pts in all:
		var v := 0.0
		var first := verts.size()
		for k in pts.size():
			var p: Vector3 = pts[k]
			var fwd: Vector3 = (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]) * Vector3(1, 0, 1)
			var side := fwd.normalized().cross(Vector3.UP) * PATH_W * 0.5
			if k > 0:
				v += p.distance_to(pts[k - 1])
			for s in [-1.0, 1.0]:
				var q: Vector3 = p + side * s
				q.y = maxf(ground(q.x, q.z), p.y - 0.05) + 0.07
				verts.append(q)
				uvs.append(Vector2(0.0 if s < 0.0 else 1.0, v))
				norms.append(Vector3.UP)
			if k > 0:
				var a: int = first + (k - 1) * 2
				idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## Each kind of space: [face colour, deeper colour, the emblem's SVG]. The emblems are drawn on a 512 square.
const FACES := {
	"B": ["#6cc0ff", "#1a5fd6", "<rect x='224' y='136' width='64' height='240' rx='24' fill='#fff'/><rect x='136' y='224' width='240' height='64' rx='24' fill='#fff'/>"],
	"R": ["#ff7a7a", "#c41a28", "<rect x='136' y='224' width='240' height='64' rx='24' fill='#fff'/>"],
	"H": ["#6ef09a", "#13924a", "<rect x='222' y='118' width='68' height='196' rx='32' fill='#fff'/><circle cx='256' cy='374' r='38' fill='#fff'/>"],
	"I": ["#ffe066", "#f08400", "<rect x='148' y='236' width='216' height='146' rx='14' fill='#fff'/><rect x='130' y='190' width='252' height='62' rx='14' fill='#fff'/><rect x='238' y='190' width='36' height='192' fill='#f6a000'/><ellipse cx='214' cy='170' rx='46' ry='26' fill='#fff'/><ellipse cx='298' cy='170' rx='46' ry='26' fill='#fff'/>"],
	"F": ["#3a3a46", "#111118", "<rect x='150' y='150' width='118' height='168' rx='14' fill='#ffd60a' stroke='#111' stroke-width='8' transform='rotate(-14 209 234)'/><rect x='238' y='176' width='118' height='168' rx='14' fill='#ef2b2d' stroke='#111' stroke-width='8' transform='rotate(12 297 260)'/>"],
	"T": ["#c79bff", "#5f25c4", "<path d='M150 236 A112 112 0 0 1 336 172' stroke='#fff' stroke-width='44' fill='none' stroke-linecap='round'/><polygon points='378,120 384,236 282,190' fill='#fff'/><path d='M362 276 A112 112 0 0 1 176 340' stroke='#fff' stroke-width='44' fill='none' stroke-linecap='round'/><polygon points='134,392 128,276 230,322' fill='#fff'/>"],
	"$": ["#5ff0de", "#0b8a80", "<rect x='156' y='206' width='200' height='178' rx='26' fill='#fff'/><path d='M200 214 V176 a56 56 0 0 1 112 0 V214' stroke='#fff' stroke-width='26' fill='none'/><circle cx='256' cy='296' r='42' fill='#0b8a80'/><rect x='246' y='262' width='20' height='68' rx='8' fill='#fff'/>"],
	"M": ["#ffb35c", "#d0520a", "<ellipse cx='256' cy='318' rx='86' ry='72' fill='#fff'/><circle cx='166' cy='222' r='34' fill='#fff'/><circle cx='222' cy='170' r='36' fill='#fff'/><circle cx='290' cy='170' r='36' fill='#fff'/><circle cx='346' cy='222' r='34' fill='#fff'/>"],
	"K": ["#ffe98a", "#d19400", "<rect x='130' y='190' width='252' height='134' rx='16' fill='#fff'/><circle cx='130' cy='257' r='26' fill='#e8b000'/><circle cx='382' cy='257' r='26' fill='#e8b000'/><rect x='196' y='230' width='120' height='16' rx='8' fill='#e8b000'/><rect x='196' y='268' width='80' height='16' rx='8' fill='#e8b000'/>"],
	"D": ["#ff9f80", "#b0361a", "<circle cx='256' cy='256' r='118' stroke='#fff' stroke-width='26' fill='none'/><circle cx='214' cy='256' r='34' fill='#fff'/><circle cx='298' cy='256' r='34' fill='#fff'/>"],
	"P": ["#c4a2ff", "#5426a8", "<path d='M256 104 c32 0 42 32 36 62 c-6 26 -22 34 -12 60 c14 36 52 70 52 122 c0 42 -38 62 -76 62 c-38 0 -76 -20 -76 -62 c0 -52 38 -86 52 -122 c10 -26 -6 -34 -12 -60 c-6 -30 4 -62 36 -62z' fill='#fff'/><rect x='226' y='176' width='60' height='14' fill='#e5383b'/><rect x='222' y='200' width='68' height='14' fill='#e5383b'/>"],
	"C": ["#a8e2ff", "#2577c4", "<polygon points='118,380 252,136 394,380' fill='#fff'/><polygon points='212,210 252,136 292,210 270,196 252,214 232,196' fill='#d8efff'/><path d='M150 300 Q260 320 330 230' stroke='#2577c4' stroke-width='22' fill='none' stroke-linecap='round'/>"],
	"S": ["#ffffff", "#e8e8e8", ""],
}


static func icon(k: String) -> ImageTexture:
	## A space's face: a gradient disc in its colour with its emblem, on a cream rim.
	if _icons.has(k):
		return _icons[k]
	var f: Array = FACES[k]
	var face := "<circle cx='256' cy='256' r='226' fill='url(#g)'/>"
	if k == "F":  # the referee's stripes
		face = "<clipPath id='c'><circle cx='256' cy='256' r='226'/></clipPath><g clip-path='url(#c)'>"
		for s in 12:
			face += "<rect x='%d' y='0' width='22' height='512' fill='%s'/>" % [30 + s * 40, "#fafafa" if s % 2 == 0 else "#1a1a22"]
		face += "<rect x='0' y='0' width='512' height='512' fill='#000' opacity='0.12'/></g>"
	elif k == "S":  # a chequered flag
		face = "<clipPath id='c'><circle cx='256' cy='256' r='226'/></clipPath><g clip-path='url(#c)'><rect width='512' height='512' fill='#fafafa'/>"
		for y in 8:
			for x in 8:
				if (x + y) % 2 == 0:
					face += "<rect x='%d' y='%d' width='64' height='64' fill='#20202a'/>" % [x * 64, y * 64]
		face += "</g>"
	var svg: String = "<svg xmlns='http://www.w3.org/2000/svg' width='512' height='512' viewBox='0 0 512 512'><defs>" \
		+ "<radialGradient id='g' cx='42%' cy='36%' r='72%'><stop offset='0' stop-color='" + f[0] + "'/><stop offset='1' stop-color='" + f[1] + "'/></radialGradient></defs>" \
		+ "<circle cx='256' cy='256' r='255' fill='#fff6e2'/><circle cx='256' cy='256' r='238' fill='#e9d6ae'/>" + face \
		+ "<circle cx='256' cy='256' r='200' fill='none' stroke='#ffffff' stroke-opacity='0.3' stroke-width='9'/>" + f[2] + "</svg>"
	var img := Image.new()
	img.load_svg_from_string(svg, 1.0)
	img.generate_mipmaps()
	_icons[k] = ImageTexture.create_from_image(img)
	return _icons[k]


static func disc_mesh(r: float) -> ArrayMesh:
	## A space: a flat top showing the whole face texture, a bevel and a short side into the ground.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 48
	var rings := [[0.0, 0.2, 0.0], [r * 0.94, 0.2, 0.0], [r, 0.13, 0.5], [r, -0.3, 1.0]]  # radius, height, how much the normal leans out
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		for ri in rings.size() - 1:
			var quad := []
			for pair in [[ri, a0], [ri, a1], [ri + 1, a1], [ri + 1, a0]]:
				var ring: Array = rings[pair[0]]
				var d := Vector3(cos(pair[1]), 0, sin(pair[1]))
				var rad: float = minf(ring[0], r * 0.985)
				quad.append([d * ring[0] + Vector3(0, ring[1], 0), Vector3.UP.lerp(d, ring[2]).normalized(),
					Vector2(0.5 + d.x * rad / (2.0 * r), 0.5 + d.z * rad / (2.0 * r))])
			for vi in [0, 2, 1, 0, 3, 2]:
				st.set_normal(quad[vi][1])
				st.set_uv(quad[vi][2])
				st.add_vertex(quad[vi][0])
	return st.commit()


func _spaces() -> void:
	## One multimesh per kind of space, each tilted to the slope it sits on.
	var disc := disc_mesh(1.25)
	var by_kind := {}
	for i in Party.SPACES.size():
		by_kind.get_or_add(Party.kind(i), []).append(i)
	for k in by_kind:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = disc
		mm.instance_count = by_kind[k].size()
		for n in by_kind[k].size():
			var i: int = by_kind[k][n]
			var x: float = Party.SPACES[i][1]
			var z: float = Party.SPACES[i][2]
			var up := Vector3(ground(x - 0.8, z) - ground(x + 0.8, z), 1.6, ground(x, z - 0.8) - ground(x, z + 0.8)).normalized()
			up = up.lerp(Vector3.UP, 0.4).normalized()
			var bx := (Vector3.RIGHT - up * up.x).normalized()
			var b := Basis(bx, up, bx.cross(up))
			mm.set_instance_transform(n, Transform3D(b, Vector3(x, space_y[i], z)))
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = icon(k)
		mat.roughness = 0.3
		mat.metallic_specular = 0.6
		if Look.high():
			mat.clearcoat_enabled = true
			mat.clearcoat = 0.6
			mat.clearcoat_roughness = 0.2
		if k in "HFTCDP":  # the event spaces glow a little, so they read from afar
			mat.emission_enabled = true
			mat.emission_texture = mat.albedo_texture
			mat.emission_energy_multiplier = 0.25
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	var go := Label3D.new()
	go.text = "START"
	go.font = Look.title_font()
	go.font_size = 96
	go.outline_size = 22
	go.modulate = Color("ffd23f")
	go.outline_modulate = Color("1a1a22")
	go.pixel_size = 0.0075
	go.rotation_degrees.x = -90.0
	go.position = spot(0) + Vector3(0, 0.03, 0)
	add_child(go)


# ---------------------------------------------------------------- the trophy

func _trophy() -> void:
	## The trophy: a gold cup spinning over its space in a column of light, on a glowing ring.
	trophy = Node3D.new()
	add_child(trophy)
	var cup := Node3D.new()
	cup.name = "Cup"
	trophy.add_child(cup)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color("ffc93c")
	gold.metallic = 1.0
	gold.roughness = 0.18
	gold.emission_enabled = true
	gold.emission = Color("ff9d00")
	gold.emission_energy_multiplier = 0.35
	Look.mesh(cup, lathe([Vector2(0.0, 0.0), Vector2(0.55, 0.0), Vector2(0.55, 0.12), Vector2(0.42, 0.18), Vector2(0.4, 0.3),
		Vector2(0.16, 0.38), Vector2(0.11, 0.62), Vector2(0.14, 0.78), Vector2(0.36, 0.9), Vector2(0.6, 1.15), Vector2(0.7, 1.62),
		Vector2(0.74, 1.7), Vector2(0.66, 1.7), Vector2(0.58, 1.3), Vector2(0.0, 1.0)], 40), gold)
	for s in [-1.0, 1.0]:
		var handle := TorusMesh.new()
		handle.inner_radius = 0.22
		handle.outer_radius = 0.32
		var h := Look.mesh(cup, handle, gold, Vector3(s * 0.66, 1.3, 0))
		h.rotation.x = PI * 0.5
		h.scale = Vector3(1.0, 1.0, 1.3)
	var ring := TorusMesh.new()
	ring.inner_radius = 1.25
	ring.outer_radius = 1.5
	ring.ring_segments = 8
	var halo := Look.mesh(trophy, ring, Look.neon(Color("ffcf3a"), 2.0), Vector3(0, 0.05, 0))
	halo.scale = Vector3(1, 0.25, 1)
	halo.name = "Halo"
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.6
	cyl.bottom_radius = 1.1
	cyl.height = 26.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	beam.mesh = cyl
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.albedo_color = Color(1.0, 0.8, 0.3, 0.18)
	bm.albedo_texture = _fade_tex()
	beam.material_override = bm
	beam.position.y = 13.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trophy.add_child(beam)
	if not Look.fast():
		var sparks := CPUParticles3D.new()
		sparks.mesh = Look.sphere(0.06)
		sparks.material_override = Look.neon(Color("ffe08a"), 3.0)
		sparks.amount = 24
		sparks.lifetime = 2.0
		sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		sparks.emission_ring_radius = 1.2
		sparks.emission_ring_inner_radius = 0.8
		sparks.emission_ring_height = 0.1
		sparks.emission_ring_axis = Vector3.UP
		sparks.direction = Vector3.UP
		sparks.spread = 10.0
		sparks.gravity = Vector3.ZERO
		sparks.initial_velocity_min = 0.8
		sparks.initial_velocity_max = 1.6
		trophy.add_child(sparks)


static func _fade_tex() -> GradientTexture2D:
	## Bright at the bottom, gone at the top.
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 1))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 4
	t.height = 64
	return t


static func lathe(profile: Array, seg := 32) -> ArrayMesh:
	## A solid of revolution round the y axis: profile is (radius, height) from the bottom up.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		for i in profile.size() - 1:
			var p: Vector2 = profile[i]
			var q: Vector2 = profile[i + 1]
			var v := [Vector3(cos(a0) * p.x, p.y, sin(a0) * p.x), Vector3(cos(a1) * p.x, p.y, sin(a1) * p.x),
				Vector3(cos(a1) * q.x, q.y, sin(a1) * q.x), Vector3(cos(a0) * q.x, q.y, sin(a0) * q.x)]
			for vi in [0, 2, 1, 0, 3, 2]:
				st.add_vertex(v[vi])
	st.generate_normals()
	return st.commit()


# ---------------------------------------------------------------- greenery

const RECOLOR := {leafsGreen = Color("3f9a3a"), woodBark = Color("b58a5e")}  # Kenney's palms, nearer the other trees


func scatter(path: String, xforms: Array, shadows := true, range_end := 0.0) -> void:
	## Many copies of one model as multimeshes (one per mesh in the model): cheap to draw however many there are.
	if xforms.is_empty():
		return
	var scene: Node3D = load(path).instantiate()
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var local := Transform3D.IDENTITY
		var p: Node = mi
		while p != scene:
			local = (p as Node3D).transform * local
			p = p.get_parent()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mi.mesh
		for sidx in mi.mesh.get_surface_count():
			var sm = mi.mesh.surface_get_material(sidx)
			if sm is BaseMaterial3D and RECOLOR.has(sm.resource_name):
				if mm.mesh == mi.mesh:
					mm.mesh = mi.mesh.duplicate()
				var m2: BaseMaterial3D = sm.duplicate()
				m2.albedo_color = RECOLOR[sm.resource_name]
				mm.mesh.surface_set_material(sidx, m2)
		mm.instance_count = xforms.size()
		for n in xforms.size():
			mm.set_instance_transform(n, xforms[n] * local)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if range_end > 0.0:
			mmi.visibility_range_end = range_end
			mmi.visibility_range_end_margin = 10.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
	scene.free()


func _greenery(c: Dictionary) -> void:
	if not c.has("green"):
		c.green = _plant()
	for g in c.green:
		scatter(g[0], g[1], g[2], g[3])


func _plant() -> Array:
	## Trees in clumps over the lawns, pines up the mountain, palms on the beaches, bushes and flowers along the paths
	## and grass everywhere green. Returns [model, transforms, shadows, draw distance] for each multimesh.
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var dense := 0.35 if Look.fast() else 1.0
	var trees := {}
	var add := func(path: String, x: float, z: float, s: float, sink := 0.15) -> void:
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
		trees.get_or_add(path, []).append(Transform3D(b, Vector3(x, ground(x, z) - sink, z)))
	# Broadleaf clumps on the lowland, pines on the slopes
	for k in int(520 * dense):
		var c := Vector2(rng.randf_range(-110, 110), rng.randf_range(-140, 55))
		for j in rng.randi_range(2, 6):
			var x := c.x + rng.randf_range(-7, 7)
			var z := c.y + rng.randf_range(-7, 7)
			var h := ground(x, z)
			if not free_at(x, z, 2.0) or h > 34.0 or _coast(x, z) > 0.9 or _blocks_view(x, z):
				continue
			if h > 4.0 or z < -55.0:
				add.call("res://assets/props/meadow/Pine_%d.gltf" % rng.randi_range(1, 5), x, z, rng.randf_range(0.8, 1.3), 0.3)
			elif rng.randf() < 0.75:
				add.call("res://assets/props/meadow/CommonTree_%d.gltf" % rng.randi_range(1, 5), x, z, rng.randf_range(0.8, 1.2))
	# Snowy firs near the top
	for k in int(90 * dense):
		var x := rng.randf_range(-70, 90)
		var z := rng.randf_range(-110, -50)
		var h := ground(x, z)
		if h > 20.0 and h < 50.0 and free_at(x, z, 1.0):
			add.call("res://assets/props/holiday/tree-snow-%s.glb" % ["a", "b", "c"][rng.randi() % 3], x, z, rng.randf_range(3.2, 4.6), 0.2)
	# Palms along the shore
	for k in int(70 * dense):
		var a := rng.randf_range(-PI, PI)
		var x := cos(a) * rng.randf_range(70, 92)
		var z := -8.0 + sin(a) * rng.randf_range(52, 64)
		if z < -30.0:
			continue
		for t in 6:  # walk inland until there's dry sand
			if ground(x, z) > SEA + 0.5:
				break
			x *= 0.97
			z = -8.0 + (z + 8.0) * 0.97
		if free_at(x, z, 0.5) and ground(x, z) < 2.0 and not _blocks_view(x, z):
			add.call(["res://assets/props/nature/tree_palmDetailedTall.glb", "res://assets/props/nature/tree_palmBend.glb",
				"res://assets/props/nature/tree_palmTall.glb"][rng.randi() % 3], x, z, rng.randf_range(4.5, 6.0), 0.1)
	for path in trees:
		out.append([path, trees[path], true, 0.0])
	# Bushes, flowers and ferns lining the paths
	var low := {}
	var low_add := func(path: String, x: float, z: float, s: float) -> void:
		low.get_or_add(path, []).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, ground(x, z) - 0.05, z)))
	for edge in edges():
		for k in edge.size():
			if k % 9 != 4 or rng.randf() > 0.55 * dense:
				continue
			var p: Vector3 = edge[k]
			var fwd: Vector3 = edge[mini(k + 1, edge.size() - 1)] - edge[maxi(k - 1, 0)]
			var side := fwd.normalized().cross(Vector3.UP) * (1.0 if rng.randf() < 0.5 else -1.0)
			var q := p + side * rng.randf_range(2.6, 3.8)
			if road(q.x, q.z) < 2.3 or not _clear_of_venues(q.x, q.z):
				continue
			var h := ground(q.x, q.z)
			if h > 18.0 or _coast(q.x, q.z) > 0.88:
				continue
			var pick := rng.randf()
			if pick < 0.35:
				low_add.call("res://assets/props/meadow/Bush_Common%s.gltf" % ("_Flowers" if rng.randf() < 0.5 else ""), q.x, q.z, rng.randf_range(0.8, 1.1))
			elif pick < 0.7:
				low_add.call("res://assets/props/meadow/Flower_%d_Group.gltf" % [3, 4][rng.randi() % 2], q.x, q.z, rng.randf_range(0.8, 1.2))
			elif pick < 0.85:
				low_add.call("res://assets/props/meadow/Fern_1.gltf", q.x, q.z, rng.randf_range(0.7, 1.0))
			else:
				low_add.call("res://assets/props/meadow/Rock_Medium_%d.gltf" % rng.randi_range(1, 3), q.x, q.z, rng.randf_range(0.35, 0.6))
	for path in low:
		out.append([path, low[path], true, 120.0])
	# Grass tufts, in chunks so far ones drop out
	var chunks := {}
	var tufts := ["res://assets/props/meadow/Grass_Common_Short.gltf", "res://assets/props/meadow/Grass_Wispy_Short.gltf",
		"res://assets/props/meadow/Grass_Common_Tall.gltf", "res://assets/props/meadow/Clover_1.gltf"]
	for k in int(5200 * dense):
		var x := rng.randf_range(-100, 100)
		var z := rng.randf_range(-70, 60)
		var h := ground(x, z)
		if h < 0.0 or h > 15.0 or _coast(x, z) > 0.86 or road(x, z) < 1.9 or not _clear_of_venues(x, z):
			continue
		var key := Vector2i(floori(x / 40.0), floori(z / 40.0))
		var bag: Dictionary = chunks.get_or_add(key, {})
		bag.get_or_add(tufts[rng.randi() % (4 if rng.randf() < 0.85 else 3)], []).append(
			Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.6, 1.0)), Vector3(x, h - 0.05, z)))
	for key in chunks:
		for path in chunks[key]:
			out.append([path, chunks[key][path], false, 70.0])
	return out


func _blocks_view(x: float, z: float) -> bool:
	## The board's camera looks north over the pieces: a tall tree just south of a path would hide them.
	for d in [2.0, 5.0, 8.0, 11.0, 14.0]:
		if road(x, z - d) < 3.5:
			return true
	return false


func _clear_of_venues(x: float, z: float) -> bool:
	for t in _taken:
		if Vector2(x, z).distance_to(t[0]) < t[1]:
			return false
	return true
