class_name BowlerModel
extends Node3D
## The bowler's look: a bean body with an outfit painted by a shader, a face with expressions, noodle arms,
## gloves, bowling shoes and a hat. Built from a skin Dictionary (see Skins), so every slot can be swapped.
## It's purely visual. Beast drives it each frame with pose(); menus use it for previews.

const BODY_SHADER := """
shader_type spatial;
uniform vec3 base : source_color = vec3(1.0);
uniform vec3 accent : source_color = vec3(1.0);
uniform int pattern = 0;
uniform float flash = 0.0;
uniform float coat = 0.0;  // high graphics: glossy vinyl with a little light passing through
// High graphics: the face is painted onto the body (Fall Guys / Super Battle Golf style) instead of built from spheres.
uniform bool painted_face = false;
uniform int eye_kind = 0;  // Skins.SLOTS.eyes index
uniform int mouth_kind = 0;  // Skins.SLOTS.mouth index
uniform int mood = 0;  // 0 idle, 1 angry, 2 hurt, 3 woozy, 4 happy, 5 knocked out
uniform float blink = 0.0;  // 1 = lids shut
uniform vec2 look = vec2(0.0);  // pupils, -1..1
const vec3 INK = vec3(0.07, 0.05, 0.11);
const vec3 WHITE = vec3(0.98, 0.97, 0.95);
const vec3 MOUTH_IN = vec3(0.34, 0.05, 0.1);
const vec3 TONGUE = vec3(0.96, 0.43, 0.52);
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float sd_ellipse(vec2 p, vec2 r) {
	float k0 = length(p / r);
	float k1 = length(p / (r * r));
	return k0 * (k0 - 1.0) / max(k1, 1e-5);
}
float sd_seg(vec2 p, vec2 a, vec2 b, float r) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0)) - r;
}
float sd_rbox(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}
float ink(float d, float aa) { return 1.0 - smoothstep(-aa, aa, d); }
vec3 paint(vec3 dst, vec3 c, float a) { return mix(dst, c, clamp(a, 0.0, 1.0)); }

vec3 eye(vec3 o, vec2 q, vec2 r, float s, float aa, inout vec3 em) {
	// q: point relative to the eye centre; s: -1 left eye, +1 right eye, 0 cyclops
	if (mood == 5) {  // knocked out: X
		float d = min(sd_seg(q, -r.xx * 0.7, r.xx * 0.7, 0.017), sd_seg(q, vec2(-r.x, r.x) * 0.7, vec2(r.x, -r.x) * 0.7, 0.017));
		return paint(o, INK, ink(d, aa));
	}
	if (mood == 2) {  // hurt: squeezed shut, > <
		vec2 tip = vec2(-s * r.x * 0.55, 0.0);
		float d = min(sd_seg(q, vec2(s * r.x * 0.7, r.y * 0.55), tip, 0.017), sd_seg(q, vec2(s * r.x * 0.7, -r.y * 0.55), tip, 0.017));
		return paint(o, INK, ink(d, aa));
	}
	if (mood == 4) {  // happy: closed smiling arcs
		float d = abs(length(q + vec2(0.0, r.y * 0.45)) - r.x * 0.8) - 0.016;
		d = max(d, -(q.y + r.y * 0.05));
		return paint(o, INK, ink(d, aa));
	}
	float de = sd_ellipse(q, r);
	float inside = ink(de, aa);
	o = paint(o, INK, ink(de - 0.014, aa));
	o = paint(o, WHITE, inside);
	vec2 pc = look * r * 0.42 + vec2(0.0, -r.y * 0.06);
	float pr = r.x * (eye_kind == 3 ? 0.42 : 0.56);
	float dp = length(q - pc) - pr;
	vec3 pcol = INK;
	if (eye_kind == 8) {  // laser: glowing red
		pcol = vec3(1.0, 0.12, 0.14);
		em += pcol * 2.5 * ink(dp, aa) * inside;
	}
	if (eye_kind == 9) {  // sparkle: gold four-point stars
		pcol = vec3(1.0, 0.76, 0.18);
		dp = min(sd_ellipse(q - pc, vec2(pr * 1.15, pr * 0.32)), sd_ellipse(q - pc, vec2(pr * 0.32, pr * 1.15)));
		em += pcol * 0.8 * ink(dp, aa) * inside;
	}
	o = paint(o, pcol, ink(dp, aa) * inside);
	o = paint(o, vec3(1.0), ink(length(q - pc - vec2(-pr * 0.33, pr * 0.38)) - pr * 0.3, aa) * inside);  // catch-lights
	o = paint(o, vec3(1.0), ink(length(q - pc - vec2(pr * 0.38, -pr * 0.32)) - pr * 0.13, aa) * inside);
	// Upper lid: comes down to blink, rests half shut when sleepy, slants toward the nose when angry.
	float shut = max(blink, eye_kind == 1 ? 0.45 : 0.0);
	float lid_line = r.y * (1.0 - 2.0 * shut);
	if (mood == 1 || eye_kind == 2) {
		lid_line = min(lid_line, r.y * 0.4 - (-s * q.x) * 0.9);
	}
	if (lid_line < r.y * 0.98) {
		float lid = inside * smoothstep(lid_line - aa, lid_line + aa, q.y);
		o = paint(o, base * 0.92, lid);
		o = paint(o, INK, inside * (1.0 - smoothstep(0.006, 0.006 + aa * 2.0, abs(q.y - lid_line))));
	}
	return o;
}

vec3 brow(vec3 o, vec2 q, float s, float aa) {
	float tilt = mood == 1 || eye_kind == 2 ? 1.0 : (mood == 2 ? -0.8 : (mood == 3 ? -0.5 : 0.0));
	float lift = mood == 4 ? 0.02 : 0.0;
	vec2 inner = vec2(-s * 0.055, lift - tilt * 0.025);
	vec2 outer = vec2(s * 0.06, lift + tilt * 0.02);
	if (s == 0.0) {
		inner = vec2(-0.08, lift - tilt * 0.01);
		outer = vec2(0.08, lift - tilt * 0.01);
	}
	return paint(o, INK, ink(sd_seg(q, inner, outer, 0.016), aa));
}

vec3 mouth(vec3 o, vec2 q, float aa) {
	if (mood == 5 || mood == 3) {  // knocked out or woozy: a wobbly line
		float d = max(abs(q.y - sin(q.x * 70.0) * 0.008) - 0.009, abs(q.x) - 0.065);
		return paint(o, INK, ink(d, aa));
	}
	if (mood == 2) {  // hurt: a small "oh!"
		float d = sd_ellipse(q, vec2(0.032, 0.042));
		o = paint(o, INK, ink(d - 0.013, aa));
		return paint(o, MOUTH_IN, ink(d, aa));
	}
	if (mood == 1) {  // winding up: gritted teeth
		float d = sd_rbox(q, vec2(0.07, 0.028), 0.022);
		o = paint(o, INK, ink(d - 0.013, aa));
		o = paint(o, WHITE, ink(d, aa));
		float gaps = min(abs(q.y) - 0.003, abs(fract(q.x / 0.028 + 0.5) - 0.5) * 0.028 - 0.002);
		return paint(o, INK, ink(gaps, aa) * ink(d, aa));
	}
	if (mouth_kind == 7) {  // kiss
		float d = sd_ellipse(q, vec2(0.028, 0.034));
		o = paint(o, vec3(0.86, 0.12, 0.3), ink(d - 0.016, aa));
		o = paint(o, vec3(0.45, 0.04, 0.14), ink(d, aa));
		return paint(o, vec3(1.0, 0.7, 0.8), ink(length(q - vec2(-0.016, 0.026)) - 0.006, aa));
	}
	if ((mouth_kind == 1 || mouth_kind == 3 || mouth_kind == 5) && mood != 4) {  // closed smile
		float d = max(abs(length(q - vec2(0.0, 0.1)) - 0.11) - 0.011, q.y - 0.01);
		o = paint(o, INK, ink(d, aa));
		for (float s = -1.0; s <= 1.0; s += 2.0) {
			o = paint(o, INK, ink(sd_seg(q, vec2(s * 0.072, 0.024), vec2(s * 0.088, 0.04), 0.008), aa));
		}
		return o;
	}
	// The open grin: flat top, round bottom, teeth up top and a tongue in the bottom.
	float w = mood == 4 ? 0.1 : 0.084;
	float dep = mood == 4 ? 0.085 : 0.066;
	vec2 m = q - vec2(0.0, 0.016);
	float d = max(sd_ellipse(m, vec2(w, dep)), m.y);
	float in_m = ink(d, aa);
	o = paint(o, INK, ink(d - 0.013, aa));
	o = paint(o, MOUTH_IN, in_m);
	o = paint(o, TONGUE, ink(sd_ellipse(m - vec2(0.0, -dep * 0.78), vec2(w * 0.55, dep * 0.42)), aa) * in_m);
	if (mouth_kind == 0 || mouth_kind == 4 || mood == 4) {
		o = paint(o, WHITE, smoothstep(-0.022 - aa, -0.022 + aa, m.y) * in_m);
	}
	if (mouth_kind == 2) {  // buck teeth
		o = paint(o, WHITE, ink(sd_rbox(m - vec2(0.0, -0.022), vec2(0.03, 0.026), 0.006), aa) * in_m);
		o = paint(o, INK, ink(abs(m.x) - 0.0025, aa) * ink(sd_rbox(m - vec2(0.0, -0.022), vec2(0.03, 0.026), 0.006), aa));
	}
	if (mouth_kind == 6) {  // fangs
		for (float s = -1.0; s <= 1.0; s += 2.0) {
			vec2 f = m - vec2(s * 0.045, 0.0);
			float tri = max(abs(f.x) * 2.2 + (-f.y) * 0.9 - 0.04, f.y);
			o = paint(o, WHITE, ink(tri, aa));
		}
	}
	if (mouth_kind == 4) {  // tongue out past the lip
		vec2 tq = q - vec2(0.022, -dep - 0.012);
		float dt = sd_ellipse(tq, vec2(0.036, 0.046));
		o = paint(o, INK, ink(dt - 0.012, aa) * step(tq.y, 0.03));
		o = paint(o, TONGUE, ink(dt, aa));
		o = paint(o, vec3(0.8, 0.28, 0.36), ink(sd_seg(tq, vec2(0.0, 0.0), vec2(0.0, -0.025), 0.004), aa));
	}
	return o;
}

void fragment() {
	float u = UV.x;
	float v = UV.y;  // 0 = feet, 1 = top of the head
	float fu = fract(u - 0.25) - 0.5;  // 0 = middle of the front
	vec3 col = base;
	vec3 em = vec3(0.0);
	float metal = 0.0;
	float shirt = 1.0 - smoothstep(0.54, 0.56, v);  // clothes cover the lower body
	if (pattern == 0) {  // plain: lighter belly
		float b = length(vec2(fu * 3.2, (v - 0.33) * 2.3));
		col = mix(col, mix(base, vec3(1.0), 0.4), smoothstep(0.62, 0.58, b));
	} else if (pattern == 1) {  // bowling shirt: two-tone with racing stripes and a collar
		vec3 s = accent;
		s = mix(s, mix(base, vec3(1.0), 0.25), step(abs(abs(fu) - 0.14), 0.03));
		float collar = smoothstep(0.03, 0.0, abs(v - 0.545 + abs(fu) * 0.5)) * step(abs(fu), 0.16);
		s = mix(s, vec3(0.96), collar);
		s = mix(s, vec3(0.96), step(length(vec2(fu * 6.0, fract(v * 8.0) - 0.5)), 0.12) * step(abs(fu), 0.03) * step(v, 0.5));
		col = mix(col, s, shirt);
	} else if (pattern == 2) {  // sailor stripes
		col = mix(col, mix(accent, vec3(0.97), step(0.5, fract(v * 10.0))), shirt);
	} else if (pattern == 3) {  // polka dots all over
		vec2 c = fract(vec2(u * 14.0, v * 7.0)) - 0.5;
		col = mix(col, accent, step(length(c), 0.2) * step(v, 0.7));
	} else if (pattern == 4) {  // hot-rod flames
		float edge = 0.3 + 0.12 * sin(u * 63.0 + v * 6.0) + 0.05 * sin(u * 157.0);
		vec3 fc = mix(vec3(1.0, 0.85, 0.2), vec3(1.0, 0.25, 0.05), clamp((edge - v) * 5.0, 0.0, 1.0));
		float f = smoothstep(edge + 0.02, edge - 0.02, v);
		col = mix(col, fc, f);
		em = fc * f * 0.4;
	} else if (pattern == 5) {  // tux with a bow tie
		vec3 s = mix(vec3(0.07, 0.06, 0.09), vec3(0.97), step(abs(fu), (0.56 - v) * 0.35));
		vec2 bt = vec2(fu * 10.0, (v - 0.52) * 18.0);
		s = mix(s, accent, step(abs(bt.y), abs(bt.x) * 0.8 + 0.3) * step(abs(bt.x), 0.9));
		col = mix(col, s, shirt);
	} else if (pattern == 6) {  // hawaiian shirt
		vec2 g = vec2(u * 10.0, v * 5.0);
		vec2 f2 = fract(g) - 0.5 + (vec2(h(floor(g)), h(floor(g) + 3.1)) - 0.5) * 0.4;
		float r = length(f2);
		vec3 s = mix(accent, vec3(1.0, 0.95, 0.85), step(r, 0.18 + 0.08 * cos(atan(f2.y, f2.x) * 5.0)));
		s = mix(s, vec3(1.0, 0.8, 0.1), step(r, 0.06));
		col = mix(col, s, shirt);
	} else if (pattern == 7) {  // checkerboard
		col = mix(col, mix(accent, vec3(0.97), mod(floor(u * 16.0) + floor(v * 8.0), 2.0)), shirt);
	} else if (pattern == 8) {  // 90s zigzag
		float z = abs(fract(u * 12.0) - 0.5) * 0.12;
		col = mix(col, accent, step(abs(v - 0.3 - z), 0.06));
		col = mix(col, vec3(0.2, 0.95, 1.0), step(abs(v - 0.45 - z), 0.03));
		em = vec3(0.2, 0.95, 1.0) * step(abs(v - 0.45 - z), 0.03) * 0.8;
	} else if (pattern == 9) {  // galaxy
		vec3 s = mix(vec3(0.08, 0.03, 0.2), accent * 0.7, (sin(u * 18.0 + v * 9.0) * 0.5 + 0.5) * 0.6);
		vec2 sg = vec2(u * 120.0, v * 60.0);
		float star = step(0.96, h(floor(sg))) * smoothstep(0.35, 0.1, length(fract(sg) - 0.5));
		col = mix(col, s + vec3(star), shirt);
		em = vec3(star) * shirt * 2.5;
	} else if (pattern == 10) {  // tiger stripes
		float s = sin(u * 50.0 + sin(v * 23.0) * 1.8 + sin(v * 7.0));
		col = mix(col, mix(vec3(1.0, 0.55, 0.1), vec3(0.06, 0.03, 0.03), step(0.55, s)), shirt);
	} else if (pattern == 11) {  // lava: cooled rock with glowing cracks
		float c = abs(sin(u * 31.0 + sin(v * 17.0) * 2.0) * sin(v * 23.0 + sin(u * 13.0) * 3.0));
		float crack = smoothstep(0.12, 0.0, c);
		vec3 hot = mix(vec3(1.0, 0.35, 0.05), vec3(1.0, 0.85, 0.2), crack);
		col = mix(col, mix(vec3(0.13, 0.07, 0.07), hot, crack), shirt);
		em = hot * crack * shirt * 2.0;
	} else if (pattern == 12) {  // solid gold suit with glints
		vec2 sg = vec2(u * 80.0, v * 40.0);
		float glint = step(0.97, h(floor(sg))) * smoothstep(0.4, 0.1, length(fract(sg) - 0.5));
		col = mix(col, vec3(1.0, 0.76, 0.2) * (0.85 + 0.15 * sin(v * 30.0)) + vec3(glint), shirt);
		em = (vec3(1.0, 0.9, 0.5) * glint * 2.0 + vec3(0.25, 0.16, 0.0)) * shirt;  // a warm glow reads as gold without reflections
		metal = shirt * 0.3;
	} else if (pattern == 13) {  // rainbow bands
		vec3 rb = 0.55 + 0.45 * cos(6.2832 * (v * 2.2 + u * 0.3 + vec3(0.0, 0.33, 0.67)));
		col = mix(col, rb, shirt);
		em = rb * shirt * 0.15;
	}
	if (painted_face) {
		vec2 p = vec2(fu * 6.2832 * 0.42, v * 1.5 - 0.75);  // metres across the front of the face
		if (abs(p.x) < 0.45 && p.y > -0.05 && p.y < 0.75) {
			float aa = fwidth(p.x) * 1.1;
			if (mood == 0 || mood == 4) {  // rosy cheeks
				for (float s = -1.0; s <= 1.0; s += 2.0) {
					col = mix(col, vec3(1.0, 0.45, 0.5), 0.3 * ink(sd_ellipse(p - vec2(s * 0.215, 0.255), vec2(0.05, 0.028)), aa * 3.0));
				}
			}
			if (eye_kind != 5 && eye_kind != 7) {  // shades and visor are 3D and cover the eyes
				if (eye_kind == 4) {
					col = eye(col, p - vec2(0.0, 0.41), vec2(0.125, 0.145), 0.0, aa, em);
					if (mood != 5) { col = brow(col, p - vec2(0.0, 0.6), 0.0, aa); }
				} else {
					vec2 r = eye_kind == 3 ? vec2(0.1, 0.12) : vec2(0.085, 0.104);
					for (float s = -1.0; s <= 1.0; s += 2.0) {
						col = eye(col, p - vec2(s * 0.145, 0.39), r, s, aa, em);
						if (mood != 5) { col = brow(col, p - vec2(s * 0.145, 0.535), s, aa); }
					}
				}
			}
			col = mouth(col, p - vec2(0.0, 0.165), aa);
		}
	}
	ALBEDO = col;
	METALLIC = metal;
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = 0.18;
	SSS_STRENGTH = coat * 0.3;
	ROUGHNESS = 0.32;
	RIM = 0.5;
	RIM_TINT = 0.3;
	EMISSION = em + vec3(flash);
}
"""

const BODY_H := 1.5
const SHOULDER := Vector3(0.36, 0.12, -0.05)

static var _body_mesh: ArrayMesh
static var _body_shader: Shader

var color := Color.WHITE
var _painted := false  # high graphics: the face is painted by the body shader
var skin := {}
var _upper: Node3D  # body + face + hat: leans as one piece
var _body_mat: ShaderMaterial
var _eyes: Array[Node3D] = []
var _pupils: Array[Node3D] = []
var _xeyes: Array[Node3D] = []
var _lids: Array[Node3D] = []
var _brows: Array[Node3D] = []
var _mouth: Node3D
var _fists: Array[Node3D] = []
var _arms: Array[MeshInstance3D] = []
var _feet: Array[Node3D] = []
var _spinner: Node3D  # propeller blades
var _halo: Node3D
var _phase := 0.0
var _lean := 0.0
var _lean_v := 0.0
var _lean_axis := Vector3.RIGHT
var _squash := Vector3.ONE
var _shake := 0.0
var _hurt := 0.0
var _blink := 2.0
var _googly := Vector2.ZERO


func build(c: Color, s: Dictionary) -> void:
	color = c
	skin = Skins.sanitize(s)
	for ch in get_children():
		ch.free()
	_eyes.clear(); _pupils.clear(); _xeyes.clear(); _lids.clear(); _brows.clear(); _fists.clear(); _arms.clear(); _feet.clear()
	_spinner = null
	_halo = null
	var accent: Color = Skins.ACCENTS[skin.accent]

	_upper = Node3D.new()
	add_child(_upper)
	if _body_shader == null:
		_body_shader = Shader.new()
		_body_shader.code = BODY_SHADER
	_body_mat = ShaderMaterial.new()
	_body_mat.shader = _body_shader
	_body_mat.set_shader_parameter("base", color)
	_body_mat.set_shader_parameter("accent", accent)
	_body_mat.set_shader_parameter("pattern", Skins.SLOTS.outfit.find(skin.outfit))
	_body_mat.set_shader_parameter("coat", 0.6 if Look.high() else 0.0)
	_painted = Look.high()
	_body_mat.set_shader_parameter("painted_face", _painted)
	_body_mat.set_shader_parameter("eye_kind", Skins.SLOTS.eyes.find(skin.eyes))
	_body_mat.set_shader_parameter("mouth_kind", Skins.SLOTS.mouth.find(skin.mouth))
	_body_mat.next_pass = Look.outline()
	var body := MeshInstance3D.new()
	body.mesh = _bean()
	body.material_override = _body_mat
	_upper.add_child(body)

	_build_eyes(accent)
	_build_mouth(accent)
	_build_hat(accent)

	var skin_mat := Look.toy(color, 0.35)
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var tube := CylinderMesh.new()
		tube.top_radius = 0.075
		tube.bottom_radius = 0.065
		tube.height = 1.0
		tube.radial_segments = 10
		tube.rings = 1
		arm.mesh = tube
		arm.material_override = skin_mat
		add_child(arm)
		_arms.append(arm)
		_fists.append(_glove(side))
		_feet.append(_shoe(side))


# ------------------------------------------------------------------ parts

func _bean() -> ArrayMesh:
	# Lathe-turned bean with UVs (u around, v up) and analytic normals so the outfit shader wraps cleanly.
	if _body_mesh:
		return _body_mesh
	var prof := [[-0.75, 0.0], [-0.73, 0.18], [-0.68, 0.31], [-0.58, 0.41], [-0.42, 0.465], [-0.2, 0.475],
		[0.05, 0.46], [0.28, 0.43], [0.46, 0.39], [0.58, 0.33], [0.67, 0.25], [0.72, 0.16], [0.745, 0.08], [0.75, 0.0]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 32
	var nrm := []
	for i in prof.size():
		var a: Array = prof[maxi(i - 1, 0)]
		var b: Array = prof[mini(i + 1, prof.size() - 1)]
		nrm.append(Vector2(b[0] - a[0], -(b[1] - a[1])).normalized())  # (radial, up) outward normal
	for i in prof.size() - 1:
		for s in seg:
			var quad := []
			for c in [[i, s], [i + 1, s], [i + 1, s + 1], [i, s + 1]]:
				var ang: float = TAU * c[1] / seg
				var r: float = prof[c[0]][1]
				var y: float = prof[c[0]][0]
				var n: Vector2 = nrm[c[0]]
				quad.append([Vector3(cos(ang) * r, y, sin(ang) * r), Vector3(cos(ang) * n.x, n.y, sin(ang) * n.x).normalized(),
					Vector2(float(c[1]) / seg, (y + 0.75) / 1.5)])
			for k in [0, 2, 1, 0, 3, 2]:
				st.set_normal(quad[k][1])
				st.set_uv(quad[k][2])
				st.add_vertex(quad[k][0])
	_body_mesh = st.commit()
	return _body_mesh


func _part(parent: Node, m: Mesh, mat: Material, pos := Vector3.ZERO, scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := Look.mesh(parent, m, mat, pos)
	mi.scale = scl
	mi.rotation = rot
	return mi


func _build_eyes(accent: Color) -> void:
	var white := Look.toy(Color.WHITE, 0.15, false)
	var black := Look.toy(Color("120818"), 0.2, false)
	var kind: String = skin.eyes
	var big := 0.13 if kind == "googly" or kind == "nerd" else 0.115
	var spots := [Vector3(0, 0.42, -0.33)] if kind == "cyclops" else [Vector3(-0.15, 0.38, -0.34), Vector3(0.15, 0.38, -0.34)]
	if _painted:
		spots = []  # painted on the body; only glasses and visors below are 3D
	for p in spots:
		var r := 0.17 if kind == "cyclops" else big
		var eye := Node3D.new()
		eye.position = p
		_upper.add_child(eye)
		_part(eye, Look.sphere(r), white)
		_pupils.append(_part(eye, Look.sphere(r * 0.5), black, Vector3(0, 0, -r * 0.7)))
		var x := Node3D.new()  # knocked-out X eyes
		eye.add_child(x)
		for ang in [0.785, -0.785]:
			_part(x, Look.box(Vector3(r * 1.6, r * 0.35, 0.02)), black, Vector3(0, 0, -r * 0.95), Vector3.ONE, Vector3(0, 0, ang))
		x.visible = false
		_xeyes.append(x)
		if kind == "sleepy":
			var lid := _part(eye, Look.sphere(r * 1.08), Look.toy(color, 0.35, false), Vector3(0, r * 0.35, 0), Vector3(1, 0.62, 1))
			_lids.append(lid)
		_eyes.append(eye)
	for side in ([] if _painted else [0.0] if kind == "cyclops" else [-1.0, 1.0]):
		_brows.append(_part(_upper, Look.box(Vector3(0.13 if kind != "cyclops" else 0.22, 0.035, 0.04)), black,
			Vector3(side * 0.15, 0.53, -0.32)))
	if kind == "angry":
		for i in _brows.size():
			_brows[i].rotation.z = -0.45 * (-1.0 if i == 0 else 1.0)
	match kind:
		"shades":
			var lens := Look.toy(Color("0d0a12"), 0.05, false)
			lens.metallic = 0.6
			for side in [-1.0, 1.0]:
				_part(_upper, Look.box(Vector3(0.22, 0.14, 0.06)), lens, Vector3(side * 0.14, 0.39, -0.42))
				_part(_upper, Look.box(Vector3(0.05, 0.02, 0.07)), Look.neon(Color.WHITE, 1.0), Vector3(side * 0.14 - 0.05, 0.42, -0.455))
			_part(_upper, Look.box(Vector3(0.12, 0.03, 0.05)), lens, Vector3(0, 0.41, -0.43))
			for p in _pupils:
				p.visible = false
		"nerd":
			var frame := Look.toy(Color("2a1a10"), 0.3, false)
			for side in [-1.0, 1.0]:
				var ring := TorusMesh.new()
				ring.inner_radius = 0.125
				ring.outer_radius = 0.15
				_part(_upper, ring, frame, Vector3(side * 0.15, 0.38, -0.43), Vector3.ONE, Vector3(PI * 0.5, 0, 0))
			_part(_upper, Look.box(Vector3(0.06, 0.025, 0.03)), frame, Vector3(0, 0.39, -0.45))
		"visor":
			_part(_upper, Look.box(Vector3(0.56, 0.12, 0.08)), Look.neon(accent.lightened(0.2), 2.5), Vector3(0, 0.39, -0.4))
			for p in _pupils:
				p.visible = false
		"laser", "sparkle":
			var glow := Look.neon(Color("ff2030") if kind == "laser" else Color("ffd23f"), 3.0)
			for p in _pupils:
				p.material_override = glow
				if kind == "sparkle":
					_part(p, Look.sphere(0.02), Look.neon(Color.WHITE, 4.0), Vector3(0.025, 0.03, -0.03))


func _build_mouth(accent: Color) -> void:
	var black := Look.toy(Color("1a0a14"), 0.3, false)
	var white := Look.toy(Color.WHITE, 0.2, false)
	var pink := Look.toy(Color("ff6f91"), 0.3, false)
	_mouth = Node3D.new()
	_mouth.position = Vector3(0, 0.16, -0.43)
	_upper.add_child(_mouth)
	var kind: String = skin.mouth
	var open := SphereMesh.new()  # a D-shaped open mouth
	open.radius = 0.09
	open.height = 0.09
	open.is_hemisphere = true
	if _painted and not kind in ["mustache", "beard"]:
		return  # painted on the body
	match kind:
		"grin":
			_part(_mouth, Look.box(Vector3(0.26, 0.08, 0.04)), black)
			_part(_mouth, Look.box(Vector3(0.22, 0.03, 0.05)), white, Vector3(0, 0.02, 0))
		"smile", "tongue":
			_part(_mouth, open, black, Vector3.ZERO, Vector3(1.3, 1, 0.5), Vector3(PI, 0, 0))
			if kind == "tongue":
				_part(_mouth, Look.sphere(0.06), pink, Vector3(0.03, -0.08, -0.03), Vector3(1, 1.4, 0.6))
		"teeth":
			_part(_mouth, Look.box(Vector3(0.16, 0.05, 0.04)), black)
			for s in [-1.0, 1.0]:
				_part(_mouth, Look.box(Vector3(0.05, 0.07, 0.03)), white, Vector3(s * 0.028, -0.045, -0.01))
		"mustache", "beard":
			if not _painted:
				_part(_mouth, Look.box(Vector3(0.14, 0.04, 0.04)), black, Vector3(0, -0.03, 0))
			var hair := Look.toy(Color("4a2a14") if kind == "mustache" else accent.darkened(0.3), 0.6)
			for s in [-1.0, 1.0]:
				_part(_mouth, Look.sphere(0.07), hair, Vector3(s * 0.08, 0.035, -0.02), Vector3(1.5, 0.6, 0.7), Vector3(0, 0, s * 0.35))
			if kind == "beard":
				_part(_upper, Look.sphere(0.25), hair, Vector3(0, 0.02, -0.3), Vector3(1.15, 0.8, 0.6))
		"fangs":
			_part(_mouth, open, black, Vector3.ZERO, Vector3(1.3, 1, 0.5), Vector3(PI, 0, 0))
			var fang := PrismMesh.new()
			fang.size = Vector3(0.05, 0.08, 0.03)
			for s in [-1.0, 1.0]:
				_part(_mouth, fang, white, Vector3(s * 0.06, -0.035, -0.035), Vector3.ONE, Vector3(0, 0, PI))
		"kiss":
			var lips := TorusMesh.new()
			lips.inner_radius = 0.025
			lips.outer_radius = 0.06
			_part(_mouth, lips, Look.toy(Color("ff2d6f"), 0.2), Vector3(0, 0, -0.02), Vector3(1.2, 1, 1), Vector3(PI * 0.5, 0, 0))


func _build_hat(accent: Color) -> void:
	var kind: String = skin.hat
	if kind == "none":
		return
	var mat := Look.toy(accent, 0.35)
	var dark := Look.toy(accent.darkened(0.35), 0.4)
	var dome := SphereMesh.new()
	dome.radius = 0.38
	dome.height = 0.38
	dome.is_hemisphere = true
	if _painted and _model_mesh("hat_" + kind) != null:
		_model(_upper, "hat_" + kind, _roles(accent))
		if kind == "propeller":
			_spinner = Node3D.new()
			_spinner.position = Vector3(0, 1.05, 0)
			_upper.add_child(_spinner)
			_model(_spinner, "hat_propeller_blades", _roles(accent))
		return
	match kind:
		"cap":
			_part(_upper, dome, mat, Vector3(0, 0.56, 0), Vector3(1.02, 0.95, 1.02))
			_part(_upper, _cyl(0.22, 0.22, 0.03), dark, Vector3(0, 0.6, -0.36), Vector3(1, 1, 1.3))
			_part(_upper, Look.sphere(0.04), dark, Vector3(0, 0.93, 0))
		"beanie":
			_part(_upper, dome, mat, Vector3(0, 0.55, 0), Vector3(1.06, 1.2, 1.06))
			_part(_upper, _cyl(0.41, 0.41, 0.12), dark, Vector3(0, 0.6, 0))
			_part(_upper, Look.sphere(0.1), Look.toy(Color.WHITE, 0.8), Vector3(0, 1.03, 0))
		"tophat":
			var black := Look.toy(Color("15111c"), 0.3)
			_part(_upper, _cyl(0.38, 0.38, 0.03), black, Vector3(0, 0.7, 0))
			_part(_upper, _cyl(0.24, 0.25, 0.46), black, Vector3(0, 0.94, 0))
			_part(_upper, _cyl(0.255, 0.255, 0.07), mat, Vector3(0, 0.75, 0))
		"cone":
			var orange := Look.toy(Color("ff6a1a"), 0.4)
			_part(_upper, Look.box(Vector3(0.6, 0.05, 0.6)), orange, Vector3(0, 0.71, 0))
			_part(_upper, _cyl(0.04, 0.27, 0.6), orange, Vector3(0, 1.02, 0))
			_part(_upper, _cyl(0.15, 0.2, 0.08), Look.toy(Color.WHITE, 0.3, false), Vector3(0, 0.93, 0))
		"viking":
			var metal := Look.toy(Color("9aa0ad"), 0.25)
			metal.metallic = 0.7
			_part(_upper, dome, metal, Vector3(0, 0.55, 0), Vector3(1.08, 0.9, 1.08))
			for s in [-1.0, 1.0]:
				_part(_upper, _cyl(0.012, 0.08, 0.38), Look.toy(Color("f3e7c9"), 0.4), Vector3(s * 0.43, 0.82, 0), Vector3.ONE, Vector3(0, 0, -s * 0.8))
		"afro":
			var hair := Look.toy(accent.darkened(0.15), 0.8)
			for i in 16:
				var a := TAU * i / 8.0
				var y := 0.62 + (0.22 if i >= 8 else 0.0)
				var r := 0.33 if i < 8 else 0.2
				_part(_upper, Look.sphere(0.17), hair, Vector3(cos(a) * r, y, sin(a) * r + 0.05))
			_part(_upper, Look.sphere(0.2), hair, Vector3(0, 0.98, 0.05))
		"mohawk":
			var spike := PrismMesh.new()
			spike.size = Vector3(0.06, 0.3, 0.16)
			for i in 5:
				_part(_upper, spike, Look.neon(accent, 0.6), Vector3(0, 0.82 - absf(i - 2) * 0.04, -0.24 + i * 0.12), Vector3.ONE, Vector3(0, PI * 0.5, 0))
		"propeller":
			_part(_upper, dome, mat, Vector3(0, 0.56, 0), Vector3(1.02, 0.95, 1.02))
			_part(_upper, _cyl(0.02, 0.02, 0.14), dark, Vector3(0, 0.98, 0))
			_spinner = Node3D.new()
			_spinner.position = Vector3(0, 1.05, 0)
			_upper.add_child(_spinner)
			for s in [-1.0, 1.0]:
				_part(_spinner, Look.box(Vector3(0.34, 0.02, 0.08)), Look.toy(Skins.ACCENTS.yellow if accent != Skins.ACCENTS.yellow else Skins.ACCENTS.red, 0.3), Vector3(s * 0.17, 0, 0), Vector3.ONE, Vector3(s * 0.3, 0, 0))
		"pin":
			_part(_upper, Arena.pin_mesh(), Arena.pin_material(), Vector3(0, 0.66, 0), Vector3.ONE * 0.42)
		"party":
			_part(_upper, _cyl(0.01, 0.2, 0.46), mat, Vector3(0.05, 0.92, 0), Vector3.ONE, Vector3(0, 0, -0.2))
			_part(_upper, Look.sphere(0.07), Look.toy(Color.WHITE, 0.6), Vector3(0.1, 1.15, 0))
		"headband":
			_part(_upper, _cyl(0.415, 0.405, 0.11), mat, Vector3(0, 0.5, 0))
		"halo":
			var ring := TorusMesh.new()
			ring.inner_radius = 0.22
			ring.outer_radius = 0.27
			_halo = _part(_upper, ring, Look.neon(Color("ffe680"), 2.5), Vector3(0, 1.0, 0))
		"cowboy":
			var leather := Look.toy(Color("8a5a32"), 0.6)
			_part(_upper, _cyl(0.56, 0.56, 0.035), leather, Vector3(0, 0.68, 0), Vector3(1, 1, 0.85))
			for s in [-1.0, 1.0]:  # brim curled up at the sides
				_part(_upper, _cyl(0.2, 0.2, 0.03), leather, Vector3(s * 0.46, 0.75, 0), Vector3(0.5, 1, 1.6), Vector3(0, 0, s * 0.7))
			_part(_upper, _cyl(0.26, 0.29, 0.3), leather, Vector3(0, 0.85, 0))
			_part(_upper, _cyl(0.292, 0.292, 0.06), dark, Vector3(0, 0.74, 0))
		"chef":
			var white := Look.toy(Color("fbfaf6"), 0.7)
			_part(_upper, _cyl(0.3, 0.3, 0.2), white, Vector3(0, 0.72, 0))
			for i in 5:
				var a := TAU * i / 5.0
				_part(_upper, Look.sphere(0.17), white, Vector3(cos(a) * 0.17, 0.92, sin(a) * 0.17))
			_part(_upper, Look.sphere(0.19), white, Vector3(0, 1.0, 0))
		"bunny":
			var fur := Look.toy(Color("fbfaf6"), 0.8)
			var pink := Look.toy(Color("ff9ec4"), 0.5, false)
			for s in [-1.0, 1.0]:
				var ear := Node3D.new()
				ear.position = Vector3(s * 0.15, 0.7, 0.05)
				ear.rotation = Vector3(0.15, 0, -s * 0.2)
				_upper.add_child(ear)
				_part(ear, Look.sphere(0.1), fur, Vector3(0, 0.28, 0), Vector3(1, 3.0, 0.55))
				_part(ear, Look.sphere(0.06), pink, Vector3(0, 0.28, -0.035), Vector3(1, 3.6, 0.4))
		"wizard":
			var robe := Look.toy(Color("3b2a9a"), 0.5)
			_part(_upper, _cyl(0.46, 0.46, 0.03), robe, Vector3(0, 0.68, 0))
			_part(_upper, _cyl(0.0, 0.3, 0.8), robe, Vector3(0, 1.08, 0.03), Vector3.ONE, Vector3(-0.15, 0, 0))
			var star := PrismMesh.new()
			star.size = Vector3(0.1, 0.1, 0.02)
			for p in [Vector3(0.12, 0.95, -0.24), Vector3(-0.1, 1.15, -0.17), Vector3(0.02, 0.82, -0.29)]:
				_part(_upper, star, Look.neon(Color("ffd23f"), 2.0), p)
		"crown", "golden_pin":
			var gold := _gold()
			if kind == "golden_pin":
				_part(_upper, Arena.pin_mesh(), gold, Vector3(0, 0.66, 0), Vector3.ONE * 0.42)
			else:
				_part(_upper, _cyl(0.27, 0.27, 0.16), gold, Vector3(0, 0.76, 0))
				var spike := PrismMesh.new()
				spike.size = Vector3(0.12, 0.16, 0.05)
				for i in 6:
					var a := TAU * i / 6.0
					var tip := _part(_upper, spike, gold, Vector3(cos(a) * 0.25, 0.91, sin(a) * 0.25))
					tip.rotation.y = -a + PI * 0.5
				for i in 3:
					var a := TAU * i / 3.0 + 0.5
					_part(_upper, Look.sphere(0.04), Look.neon(Color("ff2050"), 1.2), Vector3(cos(a) * 0.272, 0.76, sin(a) * 0.272))
		"dunce":
			_part(_upper, _cyl(0.0, 0.26, 0.85), Look.toy(Color("fbfaf6"), 0.6), Vector3(0, 1.1, 0))
			_part(_upper, _cyl(0.25, 0.265, 0.09), Look.toy(Color("e8323c"), 0.5), Vector3(0, 0.73, 0))


static var _models := {}  # cosmetics.glb object name -> Mesh (high graphics; made by tools/blender/cosmetics.py)


static func _model_mesh(id: String) -> Mesh:
	if _models.is_empty():
		var scene: Node = load("res://assets/models/cosmetics.glb").instantiate()
		for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			_models[String(mi.name)] = mi.mesh
		scene.free()
	return _models.get(id)


func _model(parent: Node, id: String, roles := {}) -> MeshInstance3D:
	## A Blender-made cosmetic. Materials named after a role (Accent, Body, ShoeA...) take this bowler's colours;
	## the rest keep theirs, all in the same toy finish as everything else.
	var mesh := _model_mesh(id)
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	parent.add_child(mi)
	for i in mesh.get_surface_count():
		var src := mesh.surface_get_material(i) as BaseMaterial3D
		var col: Color = roles.get(src.resource_name, src.albedo_color) if src else Color.WHITE
		var m := Look.toy(col, src.roughness if src else 0.4)
		if src:
			m.metallic = src.metallic
			if src.emission_enabled:
				m.emission_enabled = true
				m.emission = src.emission
				m.emission_energy_multiplier = src.emission_energy_multiplier
		mi.set_surface_override_material(i, m)
	return mi


func _roles(accent: Color) -> Dictionary:
	return {Accent = accent, AccentDark = accent.darkened(0.35), Body = color, BodyDark = color.darkened(0.1)}


func _glove(side: float) -> Node3D:
	var g := Node3D.new()
	add_child(g)
	g.position = Vector3(side * 0.55, 0.0, -0.15)
	if _painted:
		var accent: Color = Skins.ACCENTS[skin.accent]
		var roles := _roles(accent)
		var id: String = {boxing = "glove_boxing", cartoon = "glove_cartoon"}.get(skin.gloves, "glove_mitt")
		if skin.gloves == "gold":
			roles.BodyDark = Color("ffcc33")
			roles.Accent = Color("e0a810")
		if skin.gloves != "lava" and skin.gloves != "diamond":
			var mi := _model(g, id, roles)
			if mi:
				mi.scale.x = -side  # thumbs point in toward the body on both hands
				return g
	match skin.gloves:
		"boxing":
			_part(g, Look.sphere(0.19), Look.toy(Color("d4202a"), 0.15))
			_part(g, _cyl(0.12, 0.12, 0.09), Look.toy(Color.WHITE, 0.3), Vector3(0, 0, 0.17), Vector3.ONE, Vector3(PI * 0.5, 0, 0))
		"cartoon":
			_part(g, Look.sphere(0.165), Look.toy(Color.WHITE, 0.3))
			var cuff := TorusMesh.new()
			cuff.inner_radius = 0.07
			cuff.outer_radius = 0.11
			_part(g, cuff, Look.toy(Color.WHITE, 0.3), Vector3(0, 0, 0.14), Vector3.ONE, Vector3(PI * 0.5, 0, 0))
		"gold":
			_part(g, Look.sphere(0.17), _gold())
		"lava":
			_part(g, Look.sphere(0.17), Look.neon(Color("ff5a1a"), 1.6))
		"diamond":
			var gem := SphereMesh.new()  # few segments = facets
			gem.radius = 0.18
			gem.height = 0.36
			gem.radial_segments = 6
			gem.rings = 3
			var ice := Look.toy(Color("9be8ff"), 0.02)
			ice.metallic = 0.4
			ice.emission_enabled = true
			ice.emission = Color("4fd6ff")
			ice.emission_energy_multiplier = 0.4
			_part(g, gem, ice)
		_:
			_part(g, Look.sphere(0.16), Look.toy(color.darkened(0.1), 0.3))
	return g


func _shoe(side: float) -> Node3D:
	var f := Node3D.new()
	add_child(f)
	var cols: Array = Skins.SHOES[skin.shoes]
	if _painted and _model(f, "shoe_bowling", {ShoeA = cols[0], ShoeB = cols[1]}):
		f.position = Vector3(side * 0.2, -0.78, 0)
		return f
	_part(f, Look.sphere(0.15), Look.toy(cols[0], 0.3), Vector3.ZERO, Vector3(1.0, 0.6, 1.45))
	_part(f, Look.sphere(0.11), Look.toy(cols[1], 0.3), Vector3(0, 0.0, -0.11), Vector3(1.0, 0.62, 1.0))
	_part(f, Look.box(Vector3(0.24, 0.04, 0.4)), Look.toy(Color("f4f1ea"), 0.6), Vector3(0, -0.075, 0))
	f.position = Vector3(side * 0.2, -0.78, 0)
	return f


func _gold() -> StandardMaterial3D:
	## Shiny gold that still looks gold on maps without sky reflections.
	var m := Look.toy(Color("ffcc33"), 0.2)
	m.metallic = 0.45
	m.emission_enabled = true
	m.emission = Color("ffae00")
	m.emission_energy_multiplier = 0.25
	return m


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 20
	c.rings = 1
	return c


# ------------------------------------------------------------------ animation

func hit(dir_local: Vector3, power: float) -> void:
	## Jelly whiplash away from the hit, a squash, and a flash.
	dir_local.y = 0.0
	if dir_local.length() > 0.01:
		_lean_axis = Vector3.UP.cross(dir_local.normalized())
		_lean_v += 7.0 + 9.0 * power
	_squash = Vector3(1.0 + 0.25 * power, 1.0 - 0.25 * power, 1.0 + 0.25 * power)
	_hurt = 0.35
	shake(0.08 + 0.1 * power)


func shake(t: float) -> void:
	_shake = maxf(_shake, t)


func pose(dt: float, p: Dictionary) -> void:
	## p: speed, balled, holding, reaching, charging, charge (0..1), punch (Array of 0..1), hand, low, dance.
	var balled: bool = p.get("balled", false)
	var k := 1.0 - exp(-dt * 16.0)  # limb lag = jelly feel
	var t := Time.get_ticks_msec() * 0.001
	_hurt = maxf(_hurt - dt, 0.0)
	_shake = maxf(_shake - dt, 0.0)
	position = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.14 if _shake > 0.0 else Vector3.ZERO

	_squash = _squash.lerp(Vector3(1.25, 0.72, 1.25) if balled else Vector3.ONE, k)
	_lean_v += (-180.0 * _lean - 9.0 * _lean_v) * dt
	_lean += _lean_v * dt
	var bob := Vector3.ZERO
	if p.get("dance", false):
		bob = Vector3(0, absf(sin(t * 6.0)) * 0.12, 0)
		_upper.rotation.y = sin(t * 3.0) * 0.4
	_upper.basis = Basis(_lean_axis, clampf(_lean, -0.9, 0.9)) * Basis.from_scale(_squash)
	_upper.position = bob
	_body_mat.set_shader_parameter("flash", 3.0 if _hurt > 0.25 else 0.0)

	# Face
	var mood := "idle"
	if balled:
		mood = "ko"
	elif _hurt > 0.0:
		mood = "hurt"
	elif p.get("charging", false):
		mood = "angry"
	elif p.get("holding", false) or p.get("dance", false):
		mood = "happy"
	elif p.get("low", false):
		mood = "woozy"
	_blink -= dt
	if _blink < -0.12:
		_blink = randf_range(1.5, 4.0)
	for i in _eyes.size():
		var squint := 0.35 if mood == "hurt" else (0.12 if _blink < 0.0 else 1.0)
		_eyes[i].scale = _eyes[i].scale.lerp(Vector3(1, squint if mood != "ko" else 1.0, 1), 0.5)
		_xeyes[i].visible = mood == "ko"
		if skin.eyes != "shades" and skin.eyes != "visor":
			_pupils[i].visible = mood != "ko"
	if skin.eyes == "googly" or mood == "woozy":  # pupils roll around
		_googly = _googly.lerp(Vector2(sin(t * 7.0), cos(t * 5.0)) * 0.035, 0.2)
		for pu in _pupils:
			pu.position.x = _googly.x
			pu.position.y = _googly.y
	var tilt: float = {idle = 0.0, angry = -0.45, hurt = 0.4, woozy = 0.25, happy = 0.15, ko = 0.0}[mood]
	var lift: float = {idle = 0.0, angry = -0.03, hurt = 0.05, woozy = 0.02, happy = 0.04, ko = 0.0}[mood]
	for i in _brows.size():
		var s := 0.0 if _brows.size() == 1 else (-1.0 if i == 0 else 1.0)
		var base_tilt: float = -0.45 if skin.eyes == "angry" and mood == "idle" else tilt
		_brows[i].rotation.z = lerpf(_brows[i].rotation.z, -base_tilt * s, 0.3)
		_brows[i].position.y = lerpf(_brows[i].position.y, 0.53 + lift, 0.3)
		_brows[i].visible = mood != "ko"
	var ms: Vector3 = {idle = Vector3.ONE, angry = Vector3(1.15, 0.45, 1), hurt = Vector3(0.6, 1.8, 1), woozy = Vector3(0.8, 0.6, 1),
		happy = Vector3(1.25, 1.2, 1), ko = Vector3(0.9, 0.35, 1)}[mood]
	_mouth.scale = _mouth.scale.lerp(ms, 0.35)
	if _painted:
		_body_mat.set_shader_parameter("mood", {idle = 0, angry = 1, hurt = 2, woozy = 3, happy = 4, ko = 5}[mood])
		_body_mat.set_shader_parameter("blink", 1.0 if _blink < 0.0 else 0.0)
		var rolling: bool = skin.eyes == "googly" or mood == "woozy"
		_body_mat.set_shader_parameter("look", _googly / 0.035 if rolling else Vector2(sin(t * 0.7), cos(t * 0.53) * 0.5) * 0.35)
	if _spinner:
		_spinner.rotation.y += dt * (8.0 + p.get("speed", 0.0) * 4.0)
	if _halo:
		_halo.position.y = 1.0 + sin(t * 2.5) * 0.04

	# Limbs
	var speed: float = p.get("speed", 0.0)
	_phase += dt * speed * 2.4
	var walk := clampf(speed / 5.6, 0.0, 1.0) * float(not balled)
	var punch: Array = p.get("punch", [0.0, 0.0])
	for h in 2:
		var s := -1.0 if h == 0 else 1.0
		var target := Vector3(s * 0.55, sin(_phase + h * PI) * 0.05, -0.15 + sin(_phase + h * PI) * 0.3 * walk)
		if balled:
			target = Vector3(s * 0.38, 0.15, -0.38)
		elif p.get("holding", false):
			target = Vector3(s * 0.32, 0.4, -0.7)
		elif p.get("reaching", false):
			target = Vector3(s * 0.28, 0.25, -0.8)
		elif p.get("dance", false):
			target = Vector3(s * 0.5, 0.55 + sin(t * 6.0 + h * PI) * 0.2, -0.1)
		var charging_hand: bool = p.get("charging", false) and h == p.get("hand", 0)
		if charging_hand:
			target = Vector3(s * 0.5, 0.35, 0.35) + Vector3(randf(), randf(), randf()) * 0.05 * p.get("charge", 0.0)
		if punch[h] > 0.0:
			target = target.lerp(Vector3(s * 0.12, 0.3, -1.05), sin(PI * punch[h]))
		_fists[h].position = _fists[h].position.lerp(target, k if punch[h] <= 0.0 else 0.6)
		var grow := 1.0
		if charging_hand:
			grow += p.get("charge", 0.0) * 0.6 + (sin(t * 30.0) * 0.12 if p.get("charge", 0.0) >= 1.0 else 0.0)
		_fists[h].scale = Vector3.ONE * grow * (1.7 if p.get("big", false) else 1.0)
		var ft := Vector3(s * 0.2, -0.78 + maxf(0.0, cos(_phase + h * PI)) * 0.14 * walk, sin(_phase + h * PI) * 0.32 * walk)
		if balled:
			ft = Vector3(s * 0.25, -0.38, 0.1)
		_feet[h].position = _feet[h].position.lerp(ft, k)
		_feet[h].rotation.x = lerpf(_feet[h].rotation.x, -sin(_phase + h * PI) * 0.4 * walk, k)
		# Noodle arm from the (leaning) shoulder to the glove.
		var shoulder := _upper.transform * (SHOULDER * Vector3(s, 1, 1))
		var span := _fists[h].position - shoulder
		var len := maxf(span.length(), 0.05)
		_arms[h].transform = Transform3D(Basis(Quaternion(Vector3.UP, span / len)) * Basis.from_scale(Vector3(1, len, 1)), shoulder + span * 0.5)
		_arms[h].visible = not balled
