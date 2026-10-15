class_name Venues
## The venues of Party Park. Each is a node that builds itself on the park's ground, keeps itself busy (cars lap the
## speedway, the chairlift turns, someone's always pitching at the ballpark) and plays its part when the board calls
## an event: the stadium does the wave, the speedway gives lifts, the golfer drives, the ballpark hits home runs, the
## mountain avalanches, and so on. Shared materials and builders are the static functions at the bottom.

static var _mats := {}
static var _offsets := {}  # prop path -> offset that stands it centred on its spot
static var _ball_shader: Shader
static var _crowd_shader: Shader


static func build(park: Park) -> void:
	for v in [Stadium.new(), Speedway.new(), Golf.new(), Mountain.new(), Beach.new(), Ballpark.new(), Courts.new(),
			Plaza.new(), Alley.new(), Dojo.new(), Skies.new()]:
		v.park = park
		park.add_child(v)
		v.make()
		park.venues[v.id] = v
		if v.id != "skies":
			bake(v)
			tidy(v)


static func bake(root: Node3D) -> void:
	## Merge the venue's still meshes (and those in its plain sub-groups) into one mesh per material: a stadium of
	## pillars, flags and lamps costs a handful of draw calls instead of hundreds.
	var groups := {}  # material -> [SurfaceTool, count]
	var gone := []
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("live") or mi.material_override == null or not (mi.mesh is PrimitiveMesh or mi.mesh is ArrayMesh) \
				or mi.mesh.get_surface_count() != 1 or mi.material_override is ShaderMaterial:
			continue
		var p := mi.get_parent()
		var still := true
		while p != root:
			if p.has_meta("live") or p is BowlerModel or p.get_script() != null or p.owner != null:
				still = false
				break
			p = p.get_parent()
		if not still:
			continue
		var g: Array = groups.get_or_add(mi.material_override, [null, 0])
		if g[0] == null:
			g[0] = SurfaceTool.new()
			g[0].begin(Mesh.PRIMITIVE_TRIANGLES)
		g[0].append_from(mi.mesh, 0, root.global_transform.affine_inverse() * mi.global_transform)
		g[1] += 1
		gone.append(mi)
	for mat in groups:
		var mi := MeshInstance3D.new()
		mi.mesh = groups[mat][0].commit()
		mi.material_override = mat
		root.add_child(mi)
	for mi in gone:
		mi.get_parent().remove_child(mi)
		mi.queue_free()


static func tidy(root: Node) -> void:
	## Small things only draw near the camera, and the smallest cast no shadow: the park is big, and every little
	## mesh is a draw call (four more for the shadows).
	for g: GeometryInstance3D in root.find_children("*", "GeometryInstance3D", true, false):
		if g is MultiMeshInstance3D or g is CPUParticles3D or g is Label3D:
			continue
		var size := (g.global_transform * g.get_aabb()).size.length()
		if size < 3.0:
			g.visibility_range_end = 75.0
			g.visibility_range_end_margin = 6.0
		elif size < 9.0:
			g.visibility_range_end = 170.0
			g.visibility_range_end_margin = 10.0
		if size < 1.6:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


class Venue extends Node3D:
	var park: Park
	var id := ""

	func make() -> void:
		pass

	func at(x: float, z: float, dy := 0.0) -> Vector3:
		return Vector3(x, park.ground(x, z) + dy, z)

	func put(m: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = mat
		mi.position = pos
		mi.rotation = rot
		mi.scale = scl
		add_child(mi)
		return mi

	func live(n):
		## This one moves: leave it out of bake().
		n.set_meta("live", true)
		return n


# ================================================================ the stadium

class Stadium extends Venue:
	## The heart of the park: a football stadium with eight tiers of fans round the pitch, floodlights and a big
	## screen. The stadium tunnel (a toll shortcut) crosses the pitch through gaps in the stands.
	const C := Vector2(0, -1)
	const HALF := Vector2(18.5, 12.0)  # the stands' inner edge (a rounded rectangle)
	const ROUND := 6.0
	const TIERS := 8
	const TREAD := 1.0
	const RISE := 0.75
	const FRONT := 1.3
	const GAP := 3.0  # half the tunnel's width
	var _crowd: ShaderMaterial
	var _wave_t := -100.0
	var _screen: SubViewport
	var _title: Label
	var _sub: Label
	var _confetti: CPUParticles3D

	func make() -> void:
		id = "stadium"
		park.take(C, 25.0)
		var base := park.ground(C.x, C.y)
		position = Vector3(C.x, base, C.y)
		_pitch()
		_stands()
		_lights()
		_big_screen()
		_crowd_fill()
		_confetti = Venues.confetti(self, Vector3(0, 9, 0), 18.0)

	func rr(d: float, step := 1.4) -> Array:
		## The rounded rectangle d metres out from the stands' inner edge: [point, outward normal] all the way round.
		## The long sides always get points at the tunnels' edges, so the gaps are clean.
		var out := []
		var r := ROUND + d
		var corners := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
		for c in 4:
			var cc: Vector2 = corners[c] * (HALF - Vector2(ROUND, ROUND))
			var a0 := PI * 0.5 * c
			var segs := maxi(int(r * PI * 0.5 / step), 3)
			for s in segs + 1:
				var a := a0 + PI * 0.5 * s / segs
				out.append([cc + Vector2(cos(a), sin(a)) * r, Vector2(cos(a), sin(a))])
			var n_end := Vector2(cos(a0 + PI * 0.5), sin(a0 + PI * 0.5))
			var p0: Vector2 = cc + n_end * r
			var p1: Vector2 = corners[(c + 1) % 4] * (HALF - Vector2(ROUND, ROUND)) + n_end * r
			var ts := []
			var k := maxi(int(p0.distance_to(p1) / step), 1)
			for i in range(1, k):
				ts.append(float(i) / k)
			if absf(p0.y - p1.y) < 0.01:  # a long side: cut exactly at the tunnel
				for x in [-GAP, GAP]:
					var t: float = (x - p0.x) / (p1.x - p0.x)
					if t > 0.0 and t < 1.0:
						ts.append(t)
				ts.sort()
			for t in ts:
				out.append([p0.lerp(p1, t), n_end])
		return out

	func _gap(p: Vector2) -> bool:
		return absf(p.x) < GAP - 0.01 and absf(p.y) > HALF.y * 0.5

	func _stands() -> void:
		## The tiers as one mesh coloured in team blocks, plus the outer wall and the tunnels' portals.
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var team := [Color("2f6bff"), Color("e8323c"), Color("ffd23f"), Color("2f6bff"), Color("f4f1ea"), Color("e8323c")]
		for k in TIERS + 1:
			var ring := rr(k * TREAD)
			var y := FRONT + k * RISE
			for i in ring.size():
				var a: Array = ring[i]
				var b: Array = ring[(i + 1) % ring.size()]
				if _gap((a[0] + b[0]) * 0.5):
					continue
				var ang := atan2(a[0].y, a[0].x)
				var col: Color = team[int((ang + PI) / TAU * 12.0) % team.size()] if k < TIERS else Color("e9e2d2")
				if k % 2 == 1 and k < TIERS:
					col = col.darkened(0.12)
				var rise_top := y
				var rise_bot := y - (RISE if k > 0 else FRONT)
				# riser
				_quad(st, Vector3(a[0].x, rise_bot, a[0].y), Vector3(b[0].x, rise_bot, b[0].y), Vector3(b[0].x, rise_top, b[0].y),
					Vector3(a[0].x, rise_top, a[0].y), -Vector3(a[1].x, 0, a[1].y), Color("d8d0c0") if k == 0 else col.darkened(0.3))
				if k < TIERS:  # tread
					var po: Vector2 = a[0] + a[1] * TREAD
					var qo: Vector2 = b[0] + b[1] * TREAD
					_quad(st, Vector3(a[0].x, y, a[0].y), Vector3(b[0].x, y, b[0].y), Vector3(qo.x, y, qo.y), Vector3(po.x, y, po.y), Vector3.UP, col)
				else:  # the back wall, down to the ground outside: arches round the concourse, a coloured band, a blue rim
					var po: Vector2 = a[0]
					var qo: Vector2 = b[0]
					var out_n := Vector3(a[1].x, 0, a[1].y)
					var bands := [[-0.5, 3.2, Color("33415e") if i % 3 == 1 else Color("efe6d6")], [3.2, y - 1.3, Color("f3ecdf")],
						[y - 1.3, y - 0.5, col.darkened(0.05) if k < TIERS else team[int((atan2(a[0].y, a[0].x) + PI) / TAU * 12.0) % team.size()]],
						[y - 0.5, y + 1.0, Color("2f6bff")]]
					for band in bands:
						_quad(st, Vector3(qo.x, band[1], qo.y), Vector3(po.x, band[1], po.y), Vector3(po.x, band[0], po.y), Vector3(qo.x, band[0], qo.y),
							out_n, band[2])
					_quad(st, Vector3(a[0].x, y + 1.0, a[0].y), Vector3(b[0].x, y + 1.0, b[0].y), Vector3(b[0].x, y, b[0].y), Vector3(a[0].x, y, a[0].y),
						-Vector3(a[1].x, 0, a[1].y), Color("f0e8d8"))
		# the tunnels' side walls
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var x: float = sx * GAP
				var z0: float = sz * HALF.y
				var z1: float = sz * (HALF.y + TIERS * TREAD)
				var top := FRONT + TIERS * RISE + 1.0
				var n := Vector3(-sx, 0, 0)
				_quad(st, Vector3(x, -0.5, z0), Vector3(x, -0.5, z1), Vector3(x, top, z1), Vector3(x, FRONT, z0), n, Color("cfc6b4"))
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.75
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		add_child(mi)
		# pilasters round the outside
		var wall := rr(TIERS * TREAD, 1.4)
		var pil := Venues.paint(Color("e2d8c4"), 0.7)
		for i in range(0, wall.size(), 4):
			var p: Vector2 = wall[i][0] + wall[i][1] * 0.2
			if not _gap(p) and absf(absf(p.x) - GAP) > 1.0:
				put(Venues.box(Vector3(0.5, FRONT + TIERS * RISE + 1.4, 0.5)), pil, Vector3(p.x, (FRONT + TIERS * RISE + 1.4) * 0.5 - 0.5, p.y),
					Vector3(0, atan2(wall[i][1].x, wall[i][1].y), 0))
		# the facade: coloured bands and the stadium's name over each tunnel
		for sz in [1.0, -1.0]:
			var z: float = sz * (HALF.y + TIERS * TREAD + 0.3)
			var top := FRONT + TIERS * RISE + 1.0
			for sx in [-1.0, 1.0]:
				put(Venues.box(Vector3(1.0, top + 1.2, 1.0)), Venues.paint(Color("e9e2d2")), Vector3(sx * (GAP + 0.5), (top + 1.2) * 0.5 - 0.3, z))
			put(Venues.box(Vector3(2 * GAP + 2.0, 1.6, 1.0)), Venues.paint(Color("2f6bff"), 0.4), Vector3(0, top + 0.6, z))
			var l := Venues.label(self, "PARTY PARK STADIUM", Vector3(0, top + 0.62, z + sz * 0.52), 64, Color.WHITE, Color("17306e"))
			l.pixel_size = 0.009
			if sz < 0.0:
				l.rotation.y = PI
		# pennants along the rim
		var rim := rr(TIERS * TREAD + 0.2, 7.0)
		for i in rim.size():
			var p: Vector2 = rim[i][0]
			if _gap(p):
				continue
			var h := FRONT + TIERS * RISE + 1.0
			var tang := Vector2(-rim[i][1].y, rim[i][1].x)
			put(Venues.cyl(0.05, 0.06, 3.2, 6), Venues.paint(Color("f4f1ea"), 0.4, 0.6), Vector3(p.x, h + 1.6, p.y))
			put(Venues.box(Vector3(0.05, 0.8, 1.3)), Venues.paint([Color("e8323c"), Color("ffd23f"), Color("2f6bff")][i % 3], 0.6),
				Vector3(p.x + tang.x * 0.65, h + 2.7, p.y + tang.y * 0.65), Vector3(0, atan2(tang.x, tang.y), 0))

	func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
		st.set_color(col)
		st.set_normal(n)
		for v in [a, c, b, a, d, c]:
			st.add_vertex(v)

	func _pitch() -> void:
		var pm := PlaneMesh.new()
		pm.size = Vector2(2.0 * HALF.x + 0.2, 2.0 * HALF.y + 0.2)
		var mat := ShaderMaterial.new()
		mat.shader = Shader.new()
		mat.shader.code = """
shader_type spatial;
// Mown stripes and the markings of a football pitch (in metres from the centre spot).
uniform vec2 size = vec2(37.0, 24.0);
float band(float d, float w) { return 1.0 - smoothstep(w * 0.6, w, abs(d)); }
void fragment() {
	vec2 p = (UV - 0.5) * size;
	vec3 g = mix(vec3(0.20, 0.52, 0.14), vec3(0.27, 0.62, 0.19), step(0.5, fract(p.x / 3.0)));
	vec2 h = vec2(16.0, 10.0);
	float w = 0.13;
	float l = 0.0;
	l += band(abs(p.x) - h.x, w) * step(abs(p.y), h.y + w);
	l += band(abs(p.y) - h.y, w) * step(abs(p.x), h.x + w);
	l += band(p.x, w) * step(abs(p.y), h.y);
	l += band(length(p) - 3.2, w);
	l += 1.0 - smoothstep(0.2, 0.3, length(p));
	float q = h.x - abs(p.x);
	l += band(q - 5.0, w) * step(abs(p.y), 6.2);
	l += band(abs(p.y) - 6.2, w) * step(q, 5.0) * step(0.0, q);
	l += band(q - 1.8, w) * step(abs(p.y), 3.0);
	l += band(abs(p.y) - 3.0, w) * step(q, 1.8) * step(0.0, q);
	l += band(length(vec2(q - 3.6, p.y)) - 3.0, w) * step(5.0, q);
	vec3 c = mix(g, vec3(0.96, 0.97, 0.94), clamp(l, 0.0, 1.0));
	vec3 out_ring = vec3(0.17, 0.45, 0.12);
	c = mix(out_ring, c, step(abs(p.x), h.x + 1.5) * step(abs(p.y), h.y + 1.2));
	ALBEDO = c;
	ROUGHNESS = 0.92;
}
"""
		mat.set_shader_parameter("size", pm.size)
		put(pm, mat, Vector3(0, 0.03, 0))
		# goals, ad boards and corner flags
		var white := Venues.paint(Color("fafafa"), 0.3)
		var net := StandardMaterial3D.new()
		net.albedo_color = Color(1, 1, 1, 0.35)
		net.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		net.cull_mode = BaseMaterial3D.CULL_DISABLED
		for s in [-1.0, 1.0]:
			var gx: float = s * 16.0
			for z in [-2.6, 2.6]:
				put(Venues.cyl(0.08, 0.08, 2.0, 8), white, Vector3(gx, 1.0, z))
			put(Venues.cyl(0.08, 0.08, 5.3, 8), white, Vector3(gx, 2.0, 0), Vector3(PI * 0.5, 0, 0))
			put(Venues.box(Vector3(1.4, 2.0, 5.2)), net, Vector3(gx + s * 0.75, 1.0, 0))
			for z in [-10.0, 10.0]:
				put(Venues.cyl(0.03, 0.03, 1.4, 6), white, Vector3(gx, 0.7, z))
				put(Venues.box(Vector3(0.02, 0.35, 0.45)), Venues.paint(Color("ff6a00")), Vector3(gx, 1.25, z + 0.22))
		var ads := [Color("2f6bff"), Color("e8323c"), Color("ffd23f"), Color("1fd1c1")]
		var words := ["PARTY PARK", "GO TEAM!", "BOWL HARD", "SUMO SUNDAY"]
		var k := 0
		for side in [-1.0, 1.0]:
			for x0 in [-13.5, -4.5 - GAP + 1.5, 4.5 + GAP - 1.5, 13.5]:
				var x: float = x0
				if absf(x) < GAP + 1.5:
					continue
				var z: float = side * (HALF.y - 0.6)
				put(Venues.box(Vector3(7.5, 0.9, 0.2)), Venues.glow(ads[k % 4], 0.6), Vector3(x, 0.45, z))
				var l := Venues.label(self, words[k % 4], Vector3(x, 0.47, z - side * 0.12), 48, Color.WHITE, Color(0, 0, 0, 0.5))
				l.pixel_size = 0.009
				if side < 0.0:
					pass
				else:
					l.rotation.y = PI
				k += 1

	func _lights() -> void:
		## Four floodlight masts at the corners, their lamp banks aimed at the pitch.
		var steel := Venues.paint(Color("6f7b8c"), 0.4, 0.6)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var p := Vector3(sx * (HALF.x + 7.5), 0, sz * (HALF.y + 7.0))
				put(Venues.cyl(0.22, 0.42, 22.0, 8), steel, p + Vector3(0, 11.0, 0))
				var bank := Node3D.new()
				bank.position = p + Vector3(0, 22.5, 0)
				add_child(bank)
				bank.look_at(global_position + Vector3(0, -2, 0), Vector3.UP)
				var frame := MeshInstance3D.new()
				frame.mesh = Venues.box(Vector3(4.6, 2.6, 0.4))
				frame.material_override = steel
				bank.add_child(frame)
				for r in 3:
					for c in 5:
						var lamp := MeshInstance3D.new()
						lamp.mesh = Venues.box(Vector3(0.7, 0.6, 0.1))
						lamp.material_override = Venues.glow(Color("fff8e0"), 3.0)
						lamp.position = Vector3(-1.8 + c * 0.9, -0.8 + r * 0.8, -0.22)
						bank.add_child(lamp)

	func _big_screen() -> void:
		## The big screen over the north stand shows the park's name, and whatever the board puts up.
		_screen = SubViewport.new()
		_screen.size = Vector2i(640, 300)
		_screen.transparent_bg = false
		_screen.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(_screen)
		var bg := ColorRect.new()
		bg.color = Color("10183a")
		bg.size = Vector2(640, 300)
		_screen.add_child(bg)
		_title = Label.new()
		_title.add_theme_font_override("font", Look.title_font())
		_title.add_theme_font_size_override("font_size", 92)
		_title.add_theme_color_override("font_color", Color("ffd23f"))
		_title.add_theme_color_override("font_outline_color", Color("e8323c"))
		_title.add_theme_constant_override("outline_size", 14)
		_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_title.position = Vector2(0, 30)
		_title.size = Vector2(640, 150)
		_screen.add_child(_title)
		_sub = Label.new()
		_sub.add_theme_font_override("font", Look.title_font())
		_sub.add_theme_font_size_override("font_size", 44)
		_sub.add_theme_color_override("font_color", Color.WHITE)
		_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_sub.position = Vector2(0, 180)
		_sub.size = Vector2(640, 80)
		_screen.add_child(_sub)
		show_text("PARTY PARK", "Welcome, sports fans!")
		var z := -(HALF.y + TIERS * TREAD + 1.2)
		var top := FRONT + TIERS * RISE + 1.0
		var frame := Venues.paint(Color("1c2233"), 0.4, 0.5)
		put(Venues.box(Vector3(13.2, 6.6, 0.8)), frame, Vector3(0, top + 6.0, z))
		for x in [-4.0, 4.0]:
			put(Venues.box(Vector3(0.6, 6.0, 0.6)), frame, Vector3(x, top + 0.5, z - 0.2))
		var quad := QuadMesh.new()
		quad.size = Vector2(12.4, 5.8)
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_texture = _screen.get_texture()
		var scr := put(quad, sm, Vector3(0, top + 6.0, z + 0.42))
		scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	func show_text(title: String, sub := "") -> void:
		_title.text = title
		_sub.text = sub
		_screen.render_target_update_mode = SubViewport.UPDATE_ONCE

	func _crowd_fill() -> void:
		## Fans on every tier (a few empty seats), each bouncing to their own beat. The wave rolls round them.
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		var bean := CapsuleMesh.new()
		bean.radius = 0.26
		bean.height = 0.85
		bean.radial_segments = 8
		bean.rings = 3
		mm.mesh = bean
		var xf := []
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		var shirts := [Color("e8323c"), Color("2f6bff"), Color("ffd23f"), Color("2ecc71"), Color("ff8c2a"), Color("9b59ff"),
			Color("ff5fb4"), Color("1fd1c1"), Color("f4f1ea")]
		var every := 0.85 if not Look.fast() else 1.7
		for k in TIERS:
			for e in rr(k * TREAD + TREAD * 0.55, every):
				var p: Vector2 = e[0]
				if _gap(p) or rng.randf() < 0.18:
					continue
				var ang := fposmod(atan2(p.y, p.x) / TAU, 1.0)
				xf.append([Transform3D(Basis(), Vector3(p.x, FRONT + k * RISE + 0.45, p.y)), shirts[rng.randi() % shirts.size()],
					Color(rng.randf(), ang, 0, 0)])
		mm.instance_count = xf.size()
		for i in xf.size():
			mm.set_instance_transform(i, xf[i][0])
			mm.set_instance_color(i, xf[i][1])
			mm.set_instance_custom_data(i, xf[i][2])
		if Venues._crowd_shader == null:
			Venues._crowd_shader = Shader.new()
			Venues._crowd_shader.code = """
shader_type spatial;
// Fans: each bobs to their own beat; while the wave is on, a crest of fans jumping up runs round the stadium.
uniform float wave_t = -100.0;
uniform float cheer = 0.0;
varying vec3 shirt;
void vertex() {
	float ph = INSTANCE_CUSTOM.x * 6.2831;
	float bob = max(sin(TIME * (5.0 + INSTANCE_CUSTOM.x * 3.0) + ph), 0.0) * (0.05 + cheer * 0.4);
	float front = fract(wave_t * 0.3);
	float d = abs(INSTANCE_CUSTOM.y - front);
	d = min(d, 1.0 - d);
	float on = step(0.0, wave_t) * step(wave_t, 6.5);
	float lift = exp(-d * d * 260.0) * 0.95 * on;
	VERTEX.y += bob + lift;
	VERTEX.y *= 1.0 + lift * 0.3;
	shirt = COLOR.rgb;
}
void fragment() {
	ALBEDO = shirt;
	ROUGHNESS = 0.6;
}
"""
		_crowd = ShaderMaterial.new()
		_crowd.shader = Venues._crowd_shader
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _crowd
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)

	func wave() -> void:
		## The Mexican wave (and confetti).
		_wave_t = 0.0
		_confetti.restart()
		_confetti.emitting = true

	func _process(dt: float) -> void:
		if _wave_t > -50.0:
			_wave_t += dt
			_crowd.set_shader_parameter("wave_t", _wave_t)
			_crowd.set_shader_parameter("cheer", clampf(1.0 - absf(_wave_t - 3.0) / 3.5, 0.0, 1.0))
			if _wave_t > 8.0:
				_wave_t = -100.0
				_crowd.set_shader_parameter("wave_t", -100.0)


# ================================================================ the speedway

class Speedway extends Venue:
	## An oval with banked grandstands along the far straight, pit garages in the infield and race cars lapping.
	const C := Vector2(48, -40)
	const A := 22.0  # the racing line's half length and half width
	const B := 10.0
	const W := 7.0
	var lap := Curve3D.new()  # the racing line (the board's pit stop rides it)
	var _cars := []  # [node, distance, speed, lane]

	func make() -> void:
		id = "speedway"
		park.take(C, 27.0)
		var y := park.ground(C.x, C.y)
		for k in 64:
			var a := TAU * k / 64.0
			lap.add_point(Vector3(C.x + cos(a) * A, y + 0.12, C.y + sin(a) * B))
		lap.add_point(lap.get_point_position(0))
		lap.bake_interval = 0.5
		_track(y)
		_dressing(y)
		var cols := ["raceCarRed", "raceCarGreen", "raceCarOrange", "raceCarWhite"]
		for k in 4:
			var car := Venues.prop(self, "racing/" + cols[k], Vector3.ZERO, 0.0, 3.2)
			_cars.append([car, k * 30.0, 21.0 + k * 1.3, (k % 2) * 2.0 - 1.0])

	func _track(y: float) -> void:
		## Tarmac with white edges and a chequered start line, kerbs on the inside of the turns.
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var idx := PackedInt32Array()
		var kerb_v := PackedVector3Array()
		var kerb_uv := PackedVector2Array()
		var kerb_i := PackedInt32Array()
		var n := 128
		var along := 0.0
		var prev := Vector3.ZERO
		for k in n + 1:
			var a := TAU * k / n
			var p := Vector3(C.x + cos(a) * A, y + 0.1, C.y + sin(a) * B)
			var nrm := Vector3(cos(a) / A, 0, sin(a) / B).normalized()
			if k > 0:
				along += p.distance_to(prev)
			prev = p
			verts.append(p - nrm * W * 0.5)
			verts.append(p + nrm * W * 0.5)
			uvs.append(Vector2(0, along))
			uvs.append(Vector2(1, along))
			kerb_v.append(p - nrm * (W * 0.5 + 0.9) + Vector3(0, 0.02, 0))
			kerb_v.append(p - nrm * W * 0.5 + Vector3(0, 0.06, 0))
			kerb_v.append(p + nrm * W * 0.5 + Vector3(0, 0.06, 0))
			kerb_v.append(p + nrm * (W * 0.5 + 0.9) + Vector3(0, 0.02, 0))
			for q in 4:
				kerb_uv.append(Vector2(q / 3.0, along))
			if k > 0:
				var b := (k - 1) * 2
				idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
				var kb := (k - 1) * 4
				kerb_i.append_array([kb, kb + 1, kb + 4, kb + 1, kb + 5, kb + 4, kb + 2, kb + 3, kb + 6, kb + 3, kb + 7, kb + 6])
		var tarmac := ShaderMaterial.new()
		tarmac.shader = Shader.new()
		tarmac.shader.code = """
shader_type spatial;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float start_v = 0.0;
void fragment() {
	float n = texture(noise, UV * vec2(0.5, 0.06)).r;
	vec3 c = vec3(0.24, 0.25, 0.28) * (0.85 + 0.3 * n);
	float edge = step(UV.x, 0.04) + step(0.96, UV.x);
	c = mix(c, vec3(0.95), edge);
	float d = abs(UV.y - start_v);
	if (d < 1.0) {
		float chk = mod(floor(UV.x * 10.0) + floor(UV.y * 2.0), 2.0);
		c = mix(vec3(0.95), vec3(0.08), chk);
	}
	ALBEDO = c;
	ROUGHNESS = 0.7;
}
"""
		tarmac.set_shader_parameter("noise", park.tex_noise)
		tarmac.set_shader_parameter("start_v", along * 0.25)
		put(_mesh(verts, uvs, idx), tarmac, Vector3.ZERO)
		var kerb := ShaderMaterial.new()
		kerb.shader = Shader.new()
		kerb.shader.code = """
shader_type spatial;
void fragment() {
	ALBEDO = mix(vec3(0.9, 0.12, 0.12), vec3(0.97), step(0.5, fract(UV.y * 0.5)));
	ROUGHNESS = 0.6;
}
"""
		put(_mesh(kerb_v, kerb_uv, kerb_i), kerb, Vector3.ZERO)

	func _mesh(v: PackedVector3Array, uv: PackedVector2Array, idx: PackedInt32Array) -> ArrayMesh:
		var nrm := PackedVector3Array()
		nrm.resize(v.size())
		nrm.fill(Vector3.UP)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

	func _dressing(y: float) -> void:
		# grandstands behind the far straight, facing the track (and the camera)
		for k in 6:
			var x := C.x - 15.0 + k * 6.0
			Venues.prop(self, "racing/grandStandCovered" if k % 3 != 1 else "racing/grandStandAwning", Vector3(x, y, C.y - B - W * 0.5 - 4.2), 0.0, 6.0)
		# pit garages and the pit office in the infield, by the start straight
		for k in 4:
			Venues.prop(self, "racing/pitsGarage", Vector3(C.x - 9.0 + k * 4.5, y, C.y + 3.2), 0.0, 4.5)
		Venues.prop(self, "racing/pitsOfficeRoof", Vector3(C.x + 10.0, y, C.y + 3.2), 0.0, 4.5)
		Venues.prop(self, "racing/overheadLights", Vector3(C.x, y, C.y + B), 0.0, 6.0)
		Venues.prop(self, "racing/flagCheckers", Vector3(C.x + 2.0, y, C.y + B + W * 0.5 + 1.0), 0.0, 4.0)
		for k in 5:
			Venues.prop(self, "racing/tent" if k % 2 else "racing/tentLong", Vector3(C.x - 10.0 + k * 5.0, y, C.y - 3.0), 0.0, 3.0)
		for k in 8:  # banner towers and light posts round the outside
			var a := TAU * (k + 0.5) / 8.0
			var p := Vector3(C.x + cos(a) * (A + W * 0.5 + 3.0), y, C.y + sin(a) * (B + W * 0.5 + 3.0))
			if p.z > C.y + B:  # not in front of the near straight
				continue
			Venues.prop(self, "racing/bannerTowerRed" if k % 2 else "racing/bannerTowerGreen", p, rad_to_deg(-a) + 90.0, 4.0)
		for side in [-1.0, 1.0]:  # tyre barriers round the ends
			for k in 14:
				var a := (PI if side < 0.0 else 0.0) + (k - 6.5) / 14.0 * PI * 0.8
				var p := Vector3(C.x + cos(a) * (A + W * 0.5 + 1.4), y, C.y + sin(a) * (B + W * 0.5 + 1.4))
				Venues.prop(self, "racing/barrierRed" if k % 2 else "racing/barrierWhite", p, rad_to_deg(-a) + 90.0, 5.0)
		Venues.prop(self, "racing/camera_exclusive", Vector3(C.x - 12.0, y, C.y + B + W * 0.5 + 1.5), 0.0, 5.0)

	func _process(dt: float) -> void:
		var len := lap.get_baked_length()
		for c in _cars:
			c[1] = fmod(c[1] + c[2] * dt, len)
			var xf := lap.sample_baked_with_rotation(c[1], true)
			var car: Node3D = c[0]
			car.global_transform = Transform3D(xf.basis.rotated(xf.basis.y, PI).scaled(Vector3.ONE * 3.2), xf.origin + xf.basis.x * c[3] * 1.5)

	func ride(f: float) -> Transform3D:
		## A point a fraction of the way round the racing line (for the pit-stop lift).
		return lap.sample_baked_with_rotation(fposmod(f, 1.0) * lap.get_baked_length(), true)


# ================================================================ the golf course

class Golf extends Venue:
	## Rolling fairways, greens with flags, sand traps, a pond, a clubhouse, golf carts and a golfer at the tee.
	const GREENS := [Vector2(56, 13), Vector2(72, 4), Vector2(69, 24)]
	const TEE := Vector2(73, 16)
	var _carts := []
	var _cart_path := Curve3D.new()
	var _golfer: BowlerModel
	var _club: Node3D
	var _swing := -1.0
	var _ball: MeshInstance3D
	var _idle := 3.0

	func make() -> void:
		id = "golf"
		var green := Venues.paint(Color("6fd04a"), 0.7)
		var fringe := Venues.paint(Color("4a9a32"), 0.85)
		var sand := Venues.paint(Color("f3e2b0"), 0.95)
		for g in GREENS:
			put(_patch(g, 4.3, 0.04), fringe, Vector3.ZERO)
			put(_patch(g, 3.5, 0.07), green, Vector3.ZERO)
			Venues.prop(self, "minigolf/flag-large-red", at(g.x + 0.6, g.y - 0.4), 0.0, 3.5)
			put(Venues.cyl(0.18, 0.18, 0.02, 12), Venues.paint(Color("111111")), at(g.x + 0.6, g.y - 0.4, 0.07))
			park.take(g, 4.0)
		for b in [Vector2(53, 17), Vector2(75, 7), Vector2(66, 27), Vector2(61, 11)]:
			put(_patch(b, 2.2, 0.04), sand, Vector3.ZERO)
			park.take(b, 2.5)
		# the tee and the golfer
		put(Venues.box(Vector3(3.0, 0.15, 3.0)), Venues.paint(Color("6cc24a"), 0.8), at(TEE.x, TEE.y, 0.05))
		park.take(TEE, 3.0)
		_golfer = Venues.npc(self, at(TEE.x, TEE.y, 0.95), Color("2ecc71"), {hat = "cap", outfit = "checker", accent = "white"}, 1.0)
		_golfer.rotation.y = PI * 0.5
		_club = live(Node3D.new())
		_club.position = Vector3(0, 0.9, 0)
		_golfer.get_parent().add_child(_club)
		_club.position = _golfer.position + Vector3(0, 0.3, 0)
		var shaft := MeshInstance3D.new()
		shaft.mesh = Venues.cyl(0.025, 0.025, 1.2, 6)
		shaft.material_override = Venues.paint(Color("c0c4cc"), 0.3, 0.8)
		shaft.position = Vector3(0, -0.6, -0.35)
		_club.add_child(shaft)
		_ball = live(put(Venues.ball(0.12), Venues.ball_mat(5), Vector3.ZERO))
		_ball.visible = false
		# the clubhouse
		var ch := Vector2(72, 12)
		park.take(ch, 0.0)
		var cy := park.ground(ch.x, ch.y)
		put(Venues.box(Vector3(5.0, 3.4, 8.0)), Venues.paint(Color("f6f1e4"), 0.7), Vector3(ch.x, cy + 1.7, ch.y))
		var roof := put(Venues.cyl(0.0, 5.8, 2.2, 4), Venues.paint(Color("2e7d4f"), 0.6), Vector3(ch.x, cy + 4.5, ch.y), Vector3(0, PI * 0.25, 0))
		roof.scale = Vector3(0.75, 1.0, 1.15)
		put(Venues.box(Vector3(0.1, 1.6, 5.0)), Venues.glow(Color("bfe6ff"), 0.4), Vector3(ch.x - 2.52, cy + 1.8, ch.y))
		var sign := Venues.label(self, "CLUBHOUSE", Vector3(ch.x - 2.6, cy + 3.0, ch.y), 64, Color("ffffff"), Color("2e7d4f"))
		sign.rotation.y = -PI * 0.5
		sign.pixel_size = 0.01
		park.take(ch, 6.0)
		# a giant golf ball on its tee
		var gb := Vector2(64, -6)
		put(Venues.cyl(0.25, 0.08, 1.4, 10), Venues.paint(Color("ff8c2a"), 0.4), at(gb.x, gb.y, 0.7))
		put(Venues.ball(1.6), Venues.ball_mat(5), at(gb.x, gb.y, 2.95))
		park.take(gb, 2.2)
		# the carts' loop
		var loop := [Vector2(77, 10), Vector2(75, 22), Vector2(68, 30), Vector2(66, 18), Vector2(70, 2), Vector2(77, 2)]
		for k in loop.size() + 1:
			var p: Vector2 = loop[k % loop.size()]
			var prev: Vector2 = loop[(k - 1 + loop.size()) % loop.size()]
			var nxt: Vector2 = loop[(k + 1) % loop.size()]
			var h := (nxt - prev) / 6.0
			_cart_path.add_point(at(p.x, p.y, 0.05), Vector3(-h.x, 0, -h.y), Vector3(h.x, 0, h.y))
		_cart_path.bake_interval = 0.5
		for k in 2:
			_carts.append([_cart(), k * 30.0])

	func _patch(c: Vector2, r: float, dy: float) -> ArrayMesh:
		## A blob of turf (or sand) laid on the ground.
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var seg := 28
		var mid := at(c.x, c.y, dy)
		for k in seg:
			var pts := []
			for kk in [k, k + 1]:
				var a: float = TAU * kk / seg
				var rr := r * (1.0 + 0.12 * sin(a * 3.0 + c.x) + 0.08 * sin(a * 5.0 + c.y))
				pts.append(at(c.x + cos(a) * rr, c.y + sin(a) * rr, dy))
			st.set_normal(Vector3.UP)
			for v in [mid, pts[1], pts[0]]:
				st.add_vertex(v)
		return st.commit()

	func _cart() -> Node3D:
		var cart: Node3D = live(Node3D.new())
		add_child(cart)
		var white := Venues.paint(Color("f8f8f4"), 0.4)
		var body := MeshInstance3D.new()
		body.mesh = Venues.box(Vector3(1.3, 0.6, 2.2))
		body.material_override = white
		body.position.y = 0.6
		cart.add_child(body)
		var roof := MeshInstance3D.new()
		roof.mesh = Venues.box(Vector3(1.4, 0.08, 1.9))
		roof.material_override = Venues.paint(Color("2e7d4f"), 0.5)
		roof.position = Vector3(0, 1.9, 0.1)
		cart.add_child(roof)
		for x in [-0.6, 0.6]:
			for z in [-0.7, 0.8]:
				var post := MeshInstance3D.new()
				post.mesh = Venues.cyl(0.03, 0.03, 1.0, 6)
				post.material_override = white
				post.position = Vector3(x, 1.4, z)
				cart.add_child(post)
				var wheel := MeshInstance3D.new()
				wheel.mesh = Venues.cyl(0.25, 0.25, 0.18, 12)
				wheel.material_override = Venues.paint(Color("222222"), 0.8)
				wheel.position = Vector3(x * 1.05, 0.25, z)
				wheel.rotation.z = PI * 0.5
				cart.add_child(wheel)
		var bag := MeshInstance3D.new()
		bag.mesh = Venues.cyl(0.18, 0.18, 0.9, 8)
		bag.material_override = Venues.paint(Color("e8323c"), 0.6)
		bag.position = Vector3(0.3, 1.2, 1.0)
		cart.add_child(bag)
		return cart

	func _process(dt: float) -> void:
		var len := _cart_path.get_baked_length()
		for c in _carts:
			c[1] = fmod(c[1] + 4.0 * dt, len)
			var xf := _cart_path.sample_baked_with_rotation(c[1], true)
			c[0].global_transform = Transform3D(xf.basis.rotated(Vector3.UP, PI), xf.origin)
		_golfer.pose(dt, {})
		_idle -= dt
		if _idle < 0.0 and _swing < 0.0:
			_swing = 0.0
			_idle = randf_range(5.0, 9.0)
		if _swing >= 0.0:
			_swing += dt
			var f := _swing / 1.2
			_club.rotation.z = lerpf(-0.4, 2.6, smoothstep(0.0, 0.5, f)) if f < 0.5 else lerpf(2.6, -2.4, smoothstep(0.5, 0.62, f))
			if f > 0.62 and not _ball.visible:
				_ball.visible = true
			if _ball.visible:
				var g: Vector2 = GREENS[1]
				var bf := clampf((f - 0.62) / 1.4, 0.0, 1.0)
				_ball.position = at(TEE.x, TEE.y, 0.2).lerp(at(g.x, g.y, 0.2), bf) + Vector3(0, sin(PI * bf) * 14.0, 0)
			if f > 2.1:
				_swing = -1.0
				_ball.visible = false
				_club.rotation.z = -0.4

	func tee() -> Vector3:
		return at(TEE.x, TEE.y, 1.0)

	func swing() -> void:
		_swing = 0.0


# ================================================================ the mountain

class Mountain extends Venue:
	## The snowy peak behind the park: the hiking trail, a chairlift up from its foot, the ski lodge by the ski shop,
	## a ski jump off the summit, and skiers carving down the slopes.
	var cable_a: Vector3  # the chairlift's ends (the board's chairlift ride runs along the cable)
	var cable_b: Vector3
	var jump := Curve3D.new()  # the ski jump's in-run, top to lip
	var _chairs := []
	var _skiers := []
	var _snow: CPUParticles3D

	func make() -> void:
		id = "mountain"
		_chairlift()
		_lodge()
		_ski_jump()
		for k in (1 if Look.fast() else 3):
			var sk := Venues.npc(self, Vector3.ZERO, [Color("e8323c"), Color("2f6bff"), Color("ff8c2a")][k],
				{hat = "beanie", accent = ["white", "yellow", "teal"][k], outfit = "stripes"}, 0.8)
			var skis := MeshInstance3D.new()
			skis.mesh = Venues.box(Vector3(0.5, 0.05, 1.8))
			skis.material_override = Venues.paint(Color("ffd23f"), 0.4)
			skis.position.y = -0.62
			sk.add_child(skis)
			_skiers.append([sk, k * 0.33])
		_snow = Venues.confetti(self, Vector3.ZERO, 6.0, Color("f4f8ff"))
		for p in [Vector2(-16, -60), Vector2(-1, -60)]:
			Venues.prop(self, "holiday/snowman", at(p.x, p.y), randf() * 360.0, 2.2)
			park.take(p, 1.5)

	func _chairlift() -> void:
		var bottom := park.spot(Party.LIFT[0])
		var top := park.spot(Party.LIFT[1])
		var side := (top - bottom).cross(Vector3.UP).normalized()
		cable_a = bottom + side * 2.6 + Vector3(0, 5.5, 0)
		cable_b = top + side * 2.6 + Vector3(0, 5.5, 0)
		var steel := Venues.paint(Color("8a96a8"), 0.4, 0.7)
		var red := Venues.paint(Color("d9302c"), 0.5)
		for end in [[bottom, cable_a], [top, cable_b]]:  # stations: a roofed bullwheel house
			var base: Vector3 = end[0] + side * 2.6
			put(Venues.box(Vector3(2.0, 4.6, 2.0)), steel, base + Vector3(0, 2.3, 0))
			put(Venues.cyl(1.4, 1.4, 0.3, 20), red, end[1] + Vector3(0, 0.2, 0))
			var roof := put(Venues.cyl(0.0, 3.2, 1.3, 4), red, end[1] + Vector3(0, 1.3, 0), Vector3(0, PI * 0.25, 0))
			roof.scale = Vector3(1, 1, 0.8)
			park.take(Vector2(base.x, base.z), 2.5)
		var n := int(cable_a.distance_to(cable_b) / 9.0)
		for k in range(1, n):
			var p := cable_a.lerp(cable_b, float(k) / n)
			var g := park.ground(p.x, p.z)
			put(Venues.cyl(0.2, 0.3, p.y - g + 0.6, 8), steel, Vector3(p.x, (p.y + g) * 0.5, p.z))
			put(Venues.box(Vector3(0.3, 0.3, 3.4)), steel, p + Vector3(0, 0.3, 0), Vector3(0, atan2(side.x, side.z), 0))
		for off in [-1.3, 1.3]:  # the cable, up one side and down the other
			var a: Vector3 = cable_a + side * off
			var b: Vector3 = cable_b + side * off
			var c := put(Venues.cyl(0.04, 0.04, a.distance_to(b), 4), Venues.paint(Color("222831"), 0.5), (a + b) * 0.5)
			c.look_at_from_position((a + b) * 0.5, b, Vector3.UP)
			c.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		var count := int(cable_a.distance_to(cable_b) * 2.0 / 5.0)
		for k in count:
			var chair: Node3D = live(Node3D.new())
			add_child(chair)
			var hang := MeshInstance3D.new()
			hang.mesh = Venues.cyl(0.03, 0.03, 1.4, 4)
			hang.material_override = steel
			hang.position.y = -0.7
			chair.add_child(hang)
			var seat := MeshInstance3D.new()
			seat.mesh = Venues.box(Vector3(1.3, 0.12, 0.6))
			seat.material_override = Venues.paint([Color("2f6bff"), Color("ffd23f"), Color("e8323c")][k % 3], 0.5)
			seat.position.y = -1.45
			chair.add_child(seat)
			_chairs.append([chair, float(k) / count])

	func lift_point(f: float) -> Vector3:
		## The way up: f from the bottom station (0) to the top (1), on the cable's up side.
		var side := (cable_b - cable_a).cross(Vector3.UP).normalized()
		return cable_a.lerp(cable_b, f) - side * 1.3 + Vector3(0, -1.3, 0)

	func _lodge() -> void:
		## The ski lodge: log walls, a snowy roof, warm windows and a smoking chimney.
		var p := Vector2(-15.0, -56.5)
		var y := park.ground(p.x, p.y)
		park.take(p, 6.5)
		var logs := Venues.paint(Color("8a5634"), 0.85)
		put(Venues.box(Vector3(8.0, 3.6, 5.4)), logs, Vector3(p.x, y + 1.7, p.y))
		for s in [-1.0, 1.0]:
			var slab := put(Venues.box(Vector3(9.0, 0.35, 3.9)), Venues.paint(Color("f6f9ff"), 0.7), Vector3(p.x, y + 4.4, p.y + s * 1.5),
				Vector3(s * 0.62, 0, 0))
			slab.rotation = Vector3(s * 0.62, 0, 0)
		put(Venues.box(Vector3(8.2, 1.5, 0.3)), logs, Vector3(p.x, y + 3.9, p.y + 2.7))
		for x in [-2.4, 0.0, 2.4]:
			put(Venues.box(Vector3(1.3, 1.1, 0.1)), Venues.glow(Color("ffcf7a"), 1.2), Vector3(p.x + x, y + 1.9, p.y + 2.72))
		put(Venues.box(Vector3(0.9, 2.2, 0.9)), Venues.paint(Color("7c7c84"), 0.9), Vector3(p.x + 2.5, y + 5.0, p.y - 0.6))
		var sign := Venues.label(self, "SKI LODGE", Vector3(p.x, y + 3.6, p.y + 2.95), 64, Color("fff4df"), Color("5a3018"))
		sign.pixel_size = 0.009
		if not Look.fast():
			var smoke := CPUParticles3D.new()
			smoke.mesh = Venues.ball(0.35)
			smoke.material_override = Venues.paint(Color(0.9, 0.9, 0.92), 1.0)
			smoke.amount = 12
			smoke.lifetime = 3.5
			smoke.direction = Vector3.UP
			smoke.spread = 12.0
			smoke.gravity = Vector3(0.4, 0.6, 0)
			smoke.initial_velocity_min = 0.6
			smoke.initial_velocity_max = 1.0
			smoke.scale_amount_min = 0.6
			smoke.scale_amount_max = 1.6
			smoke.position = Vector3(p.x + 2.5, y + 6.2, p.y - 0.6)
			add_child(smoke)
		Venues.prop(self, "holiday/lantern", at(p.x - 4.8, p.y + 3.2), 0.0, 1.6)
		Venues.prop(self, "holiday/bench", at(p.x + 5.0, p.y + 3.0), 180.0, 1.8)

	func _ski_jump() -> void:
		## A tower behind the summit and an in-run down to a lip pointing at the bowling alley, far below.
		var top := park.spot(Party.LEG.descent)
		var land := park.spot(Party.SKI_TO)
		var dir := (land - top) * Vector3(1, 0, 1)
		dir = dir.normalized()
		var beside := dir.cross(Vector3.UP) * 4.0  # alongside the summit's space, not over it
		var start := top - dir * 6.0 + beside
		start = Vector3(start.x, park.ground(start.x, start.z) + 9.0, start.z)
		var lip := top + dir * 7.0 + beside
		lip.y = park.ground(lip.x, lip.z) + 2.2
		var mid := start.lerp(lip, 0.55)
		mid.y = lerpf(lip.y, start.y, 0.25)
		jump.add_point(start, Vector3.ZERO, (mid - start) * 0.4)
		jump.add_point(mid, (start - mid) * 0.3, (lip - mid) * 0.3)
		jump.add_point(lip + Vector3(0, 0.4, 0), (mid - lip) * 0.3, Vector3.ZERO)
		jump.bake_interval = 0.3
		var len := jump.get_baked_length()
		var wood := Venues.paint(Color("dce4ee"), 0.5, 0.3)
		var deck := Venues.paint(Color("f6f9ff"), 0.6)
		var n := int(len / 0.8)
		for k in n:
			var xf := jump.sample_baked_with_rotation(len * k / n, true)
			var slab := put(Venues.box(Vector3(2.6, 0.2, 0.9)), deck, xf.origin)
			slab.basis = xf.basis
			if k % 3 == 0:
				var g := park.ground(xf.origin.x, xf.origin.z)
				if xf.origin.y - g > 0.6:
					put(Venues.cyl(0.1, 0.12, xf.origin.y - g, 6), wood, Vector3(xf.origin.x, (xf.origin.y + g) * 0.5, xf.origin.z))
			for s in [-1.0, 1.0]:
				var rail := put(Venues.box(Vector3(0.1, 0.5, 0.9)), Venues.paint(Color("e8323c"), 0.5), xf.origin + xf.basis.x * s * 1.3 + Vector3(0, 0.3, 0))
				rail.basis = xf.basis
		put(Venues.box(Vector3(3.0, 0.3, 3.0)), wood, start + Vector3(0, -0.2, 0))
		var sign := Venues.label(self, "SKI JUMP", start + Vector3(0, 2.0, 0), 80, Color.WHITE, Color("2577c4"))
		sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sign.pixel_size = 0.012
		park.take(Vector2(start.x, start.z), 4.0)
		park.take(Vector2(mid.x, mid.z), 3.0)

	func _process(dt: float) -> void:
		var t := Time.get_ticks_msec() * 0.001
		var side := (cable_b - cable_a).cross(Vector3.UP).normalized()
		for c in _chairs:
			var f := fmod(c[1] + t * 0.018, 1.0)
			var up := f < 0.5
			var g := f * 2.0 if up else (f - 0.5) * 2.0
			var p := cable_a.lerp(cable_b, g) - side * 1.3 if up else cable_b.lerp(cable_a, g) + side * 1.3
			c[0].position = p
		for s in _skiers:  # zig-zagging down the snow behind the lodge, over and over
			var f := fmod(t * 0.035 + s[1], 1.0)
			var z := lerpf(-82.0, -60.0, f)
			var x: float = -40.0 + s[1] * 50.0 + sin(f * TAU * 3.0) * 8.0
			var dx := cos(f * TAU * 3.0) * 8.0 * TAU * 3.0 / 22.0
			var sk: BowlerModel = s[0]
			sk.position = at(x, z, 0.9)
			sk.rotation.y = atan2(-dx, -1.0) + PI
			sk.pose(dt, {speed = 0.0})

	func avalanche(from: Vector3, to: Vector3) -> void:
		## A rush of snow down the slope.
		_snow.position = from + Vector3(0, 2, 0)
		var tw := create_tween()
		_snow.restart()
		_snow.emitting = true
		tw.tween_property(_snow, "position", to + Vector3(0, 1, 0), 2.5).set_trans(Tween.TRANS_SINE)


# ================================================================ the beach

class Beach extends Venue:
	## The west shore: volleyball, parasols and towels, surfboards, a lifeguard tower, a pier with a lighthouse, boats.
	var _boats := []
	var _gulls := []
	var _players := []

	func make() -> void:
		id = "beach"
		var rng := RandomNumberGenerator.new()
		rng.seed = 21
		# volleyball
		var vc := Vector2(-66, -16)
		put(Venues.box(Vector3(9.0, 0.1, 16.0)), Venues.paint(Color("f0dca0"), 0.95), at(vc.x, vc.y, 0.02), Vector3(0, 0.3, 0))
		var court := Node3D.new()
		court.position = at(vc.x, vc.y)
		court.rotation.y = 0.3
		add_child(court)
		for z in [-8.0, 8.0]:
			Venues.put_on(court, Venues.box(Vector3(9.0, 0.03, 0.1)), Venues.paint(Color.WHITE), Vector3(0, 0.08, z))
		for x in [-4.5, 4.5]:
			Venues.put_on(court, Venues.box(Vector3(0.1, 0.03, 16.0)), Venues.paint(Color.WHITE), Vector3(x, 0.08, 0))
			Venues.put_on(court, Venues.cyl(0.07, 0.07, 2.6, 8), Venues.paint(Color("e8e8e8"), 0.4, 0.5), Vector3(x + signf(x) * 0.6, 1.3, 0))
		var net := StandardMaterial3D.new()
		net.albedo_color = Color(0.1, 0.1, 0.1, 0.55)
		net.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		net.cull_mode = BaseMaterial3D.CULL_DISABLED
		Venues.put_on(court, Venues.box(Vector3(10.2, 0.9, 0.03)), net, Vector3(0, 2.0, 0))
		for k in 2:
			var p := Venues.npc(court, Vector3(rng.randf_range(-2, 2), 0.9, -4.0 if k == 0 else 4.0), [Color("ff5fb4"), Color("1fd1c1")][k],
				{hat = "headband", outfit = "hawaiian", accent = "yellow"}, 0.9)
			p.rotation.y = 0.0 if k == 0 else PI
			_players.append(p)
		var vb: MeshInstance3D = live(Venues.put_on(court, Venues.ball(0.3), Venues.ball_mat(6), Vector3.ZERO))
		_players.append(vb)
		park.take(vc, 9.0)
		# parasols, towels, surfboards along the sand
		for k in 14:
			var z := rng.randf_range(-12, 30)
			var x := -71.0 + rng.randf_range(-2.5, 2.5)
			for t in 8:
				if park.ground(x, z) > Park.SEA + 0.4:
					break
				x += 1.0
			if not park.free_at(x, z, 0.2):
				continue
			var kind := k % 3
			if kind == 0:
				Venues.prop(self, "city/detail-parasol-%s" % ["a", "b"][k % 2], at(x, z), rng.randf() * 360.0, 7.0)
				put(Venues.box(Vector3(1.0, 0.03, 2.0)), Venues.paint([Color("ff5fb4"), Color("2f6bff"), Color("ffd23f")][k % 3], 0.9),
					at(x + 1.0, z + 0.5, 0.03), Vector3(0, rng.randf() * PI, 0))
			elif kind == 1:
				var board := put(Venues.ball(0.5), Venues.paint([Color("ff8c2a"), Color("1fd1c1"), Color("e8323c")][k % 3], 0.3),
					at(x, z, 1.1), Vector3(0.2, rng.randf() * PI, 0.1))
				board.scale = Vector3(0.9, 2.6, 0.18)
			else:
				put(Venues.ball(0.45), Venues.ball_mat(4), at(x, z, 0.45), Vector3(rng.randf(), rng.randf(), 0))
			park.take(Vector2(x, z), 1.5)
		# lifeguard tower
		var lg := Vector2(-73, 4)
		var ly := park.ground(lg.x, lg.y)
		var wood := Venues.paint(Color("e9d2a6"), 0.8)
		for x in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				put(Venues.cyl(0.1, 0.12, 3.0, 6), wood, Vector3(lg.x + x, ly + 1.5, lg.y + z))
		put(Venues.box(Vector3(2.6, 1.6, 2.6)), Venues.paint(Color("e8323c"), 0.6), Vector3(lg.x, ly + 3.8, lg.y))
		put(Venues.cyl(0.0, 2.2, 0.9, 4), Venues.paint(Color("f4f1ea"), 0.6), Vector3(lg.x, ly + 5.05, lg.y), Vector3(0, PI * 0.25, 0))
		var lgs := Venues.label(self, "LIFEGUARD", Vector3(lg.x + 1.32, ly + 3.85, lg.y), 48, Color.WHITE, Color("8a1010"))
		lgs.rotation.y = PI * 0.5
		lgs.pixel_size = 0.008
		park.take(lg, 2.5)
		# the pier and lighthouse
		var pier_a := Vector2(-74, 30)
		var pier_b := Vector2(-98, 30)
		var plank := Venues.paint(Color("b98a5a"), 0.85)
		var len := pier_a.distance_to(pier_b)
		put(Venues.box(Vector3(len, 0.25, 3.0)), plank, Vector3((pier_a.x + pier_b.x) * 0.5, 0.9, pier_a.y))
		for k in int(len / 3.0) + 1:
			for s in [-1.3, 1.3]:
				put(Venues.cyl(0.15, 0.15, 3.0, 6), plank, Vector3(pier_a.x - k * 3.0, -0.6, pier_a.y + s))
		var lh := Vector3(pier_b.x - 2.5, 0.9, pier_b.y)
		put(Venues.cyl(2.2, 2.4, 1.2, 20), Venues.paint(Color("d9d2c4"), 0.9), lh + Vector3(0, -0.2, 0))
		for k in 5:
			put(Venues.cyl(1.5 - k * 0.12, 1.62 - k * 0.12, 2.0, 16), Venues.paint(Color("e8323c") if k % 2 == 0 else Color("fafafa"), 0.5),
				lh + Vector3(0, 1.4 + k * 2.0, 0))
		put(Venues.cyl(0.9, 0.9, 1.2, 12), Venues.glow(Color("fff2b0"), 2.0), lh + Vector3(0, 11.0, 0))
		put(Venues.cyl(0.0, 1.3, 1.2, 12), Venues.paint(Color("e8323c"), 0.5), lh + Vector3(0, 12.2, 0))
		# boats bobbing offshore
		for p in [Vector2(-108, 6), Vector2(-96, -22), Vector2(-112, 44), Vector2(12, 74), Vector2(70, 60)]:
			_boats.append([_boat(p, rng), p, rng.randf() * TAU])
		for k in 4:
			var gull := Venues.gull(self)
			_gulls.append([gull, k * TAU / 4.0, rng.randf_range(10, 18)])

	func _boat(p: Vector2, rng: RandomNumberGenerator) -> Node3D:
		var b: Node3D = live(Node3D.new())
		b.position = Vector3(p.x, Park.SEA, p.y)
		b.rotation.y = rng.randf() * TAU
		add_child(b)
		var hull := MeshInstance3D.new()
		hull.mesh = Venues.ball(1.0)
		hull.material_override = Venues.paint(Color("fafafa"), 0.4)
		hull.scale = Vector3(1.3, 0.55, 3.6)
		b.add_child(hull)
		var mast := MeshInstance3D.new()
		mast.mesh = Venues.cyl(0.06, 0.08, 6.0, 6)
		mast.material_override = Venues.paint(Color("8a5634"), 0.6)
		mast.position.y = 3.2
		b.add_child(mast)
		var sail := MeshInstance3D.new()
		sail.mesh = Venues.cyl(0.0, 1.8, 5.0, 3)
		sail.material_override = Venues.paint([Color("ff8c2a"), Color("2f6bff"), Color("fafafa")][rng.randi() % 3], 0.7)
		sail.position = Vector3(0, 3.4, 0.6)
		sail.scale = Vector3(0.08, 1.0, 0.9)
		b.add_child(sail)
		return b

	func _process(dt: float) -> void:
		var t := Time.get_ticks_msec() * 0.001
		for b in _boats:
			var n: Node3D = b[0]
			n.position.y = Park.SEA + sin(t * 1.2 + b[2]) * 0.15
			n.rotation.z = sin(t * 0.9 + b[2]) * 0.06
		for g in _gulls:
			var a: float = t * 0.25 + g[1]
			var n: Node3D = g[0]
			n.position = Vector3(-66.0 + cos(a) * g[2], 12.0 + sin(t + g[1]) * 1.5, 6.0 + sin(a) * g[2])
			n.rotation.y = -a
			n.get_child(1).rotation.z = 0.35 + sin(t * 6.0 + g[1]) * 0.4
			n.get_child(2).rotation.z = -0.35 - sin(t * 6.0 + g[1]) * 0.4
		for k in 2:
			(_players[k] as BowlerModel).pose(dt, {speed = 1.5})
		var f := fmod(t * 0.5, 2.0)
		var from := Vector3(0, 2.2, -4.0) if f < 1.0 else Vector3(0, 2.2, 4.0)
		var to := Vector3(0, 2.2, 4.0) if f < 1.0 else Vector3(0, 2.2, -4.0)
		var ff := fmod(f, 1.0)
		(_players[2] as Node3D).position = from.lerp(to, ff) + Vector3(0, sin(PI * ff) * 3.5, 0)

	func gulls(at_pos: Vector3) -> void:
		## A seagull raid on whoever's standing here.
		for k in 3:
			var gull := Venues.gull(self)
			var from := at_pos + Vector3(-16 + k * 4, 9 + k, 8)
			gull.position = from
			var tw := gull.create_tween()
			tw.tween_property(gull, "position", at_pos + Vector3(k - 1, 1.5, 0), 0.8 + k * 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			tw.tween_property(gull, "position", at_pos + Vector3(18, 12 + k, -10), 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_callback(gull.queue_free)


# ================================================================ the ballpark

class Ballpark extends Venue:
	## A baseball diamond: dirt infield, bases and mound, an outfield fence with foul poles, light towers and a team
	## that never stops playing. Home runs fly over the fence.
	const HOME := Vector2(-42, 28)
	const OUT := Vector2(0.7071, -0.7071)  # towards centre field
	var _pitcher: BowlerModel
	var _batter: BowlerModel
	var _fielders := []
	var _ball: MeshInstance3D
	var _bat: Node3D
	var _t := 0.0
	var _hit := false

	func make() -> void:
		id = "ballpark"
		park.take(HOME + OUT * 12.0, 16.0)
		var y := park.ground(HOME.x, HOME.y)
		var root := Node3D.new()
		root.position = Vector3(HOME.x, y, HOME.y)
		root.rotation.y = atan2(-OUT.x, -OUT.y)  # local -z points to centre field
		add_child(root)
		var dirt := Venues.paint(Color("c98b55"), 0.95)
		var grass := Venues.paint(Color("4ea53a"), 0.85)
		var chalk := Venues.paint(Color("fafafa"), 0.6)
		var arc := MeshInstance3D.new()
		arc.mesh = _fan(15.0, 0.04)
		arc.material_override = dirt
		root.add_child(arc)
		var infield := MeshInstance3D.new()
		infield.mesh = Venues.box(Vector3(9.0, 0.04, 9.0))
		infield.material_override = grass
		infield.position = Vector3(0, 0.07, -6.36)
		infield.rotation.y = PI * 0.25
		root.add_child(infield)
		for b in [Vector3(0, 0.1, 0), Vector3(4.5, 0.12, -4.5), Vector3(0, 0.12, -9.0), Vector3(-4.5, 0.12, -4.5)]:
			Venues.put_on(root, Venues.box(Vector3(0.45, 0.08, 0.45)), chalk, b).rotation.y = PI * 0.25
		Venues.put_on(root, Venues.cyl(1.4, 1.8, 0.3, 20), dirt, Vector3(0, 0.12, -4.5))
		for s in [-1.0, 1.0]:  # foul lines out to the fence
			var line := Venues.put_on(root, Venues.box(Vector3(0.12, 0.03, 19.5)), chalk, Vector3(s * 6.9, 0.1, -6.9))
			line.rotation.y = -s * PI * 0.25
		# the outfield fence: padded panels in an arc, ads on them, yellow foul poles at the ends
		var n := 14
		for k in n:
			var a := -PI * 0.25 + PI * 0.5 * (k + 0.5) / n
			var p := Vector3(sin(a) * 20.0, 1.2, -cos(a) * 20.0)
			var panel := Venues.put_on(root, Venues.box(Vector3(20.0 * PI * 0.5 / n + 0.05, 2.4, 0.3)),
				Venues.paint(Color("2e7d4f") if k % 4 else Color("ffd23f"), 0.7), p)
			panel.rotation.y = -a
		for s in [-1.0, 1.0]:
			Venues.put_on(root, Venues.cyl(0.12, 0.12, 9.0, 8), Venues.paint(Color("ffd23f"), 0.4), Vector3(s * 14.1, 4.5, -14.1))
			var tower := Venues.put_on(root, Venues.cyl(0.25, 0.4, 16.0, 8), Venues.paint(Color("d7dde6"), 0.4, 0.6), Vector3(s * 17.0, 8.0, -9.0))
			var bank := Venues.put_on(root, Venues.box(Vector3(3.0, 1.8, 0.4)), Venues.paint(Color("3a3f4a"), 0.5, 0.5), Vector3(s * 17.0, 16.4, -9.0))
			bank.rotation = Vector3(0.4, s * 0.8, 0)
			var lamps := Venues.put_on(bank, Venues.box(Vector3(2.7, 1.5, 0.1)), Venues.glow(Color("fff8e0"), 2.5), Vector3(0, 0, -0.22))
		var board := Venues.put_on(root, Venues.box(Vector3(8.0, 4.0, 0.5)), Venues.paint(Color("1c2233"), 0.5), Vector3(0, 5.5, -21.0))
		var sl := Venues.label(root, "HOME  0  0  0\nAWAY  0  0  0", Vector3(0, 5.5, -20.7), 72, Color("ffd23f"), Color(0, 0, 0, 0))
		sl.pixel_size = 0.01
		Venues.put_on(root, Venues.box(Vector3(0.4, 3.6, 0.4)), Venues.paint(Color("1c2233")), Vector3(-2.5, 1.8, -21.0))
		Venues.put_on(root, Venues.box(Vector3(0.4, 3.6, 0.4)), Venues.paint(Color("1c2233")), Vector3(2.5, 1.8, -21.0))
		# dugouts: a bench under a roof, in each team's colour
		for s in [-1.0, 1.0]:
			var dug := Node3D.new()
			dug.position = Vector3(s * 7.0, 0, -0.5)
			dug.rotation.y = -s * PI * 0.25
			root.add_child(dug)
			Venues.put_on(dug, Venues.box(Vector3(4.0, 0.2, 1.6)), Venues.paint(Color("2b2f3a"), 0.6), Vector3(0, 1.6, 0))
			Venues.put_on(dug, Venues.box(Vector3(4.0, 1.5, 0.15)), Venues.paint(Color("2f6bff") if s < 0 else Color("e8323c"), 0.6), Vector3(0, 0.75, 0.75))
			Venues.put_on(dug, Venues.box(Vector3(3.6, 0.4, 0.5)), Venues.paint(Color("c08a4a"), 0.7), Vector3(0, 0.2, 0.35))
			for x in [-1.9, 1.9]:
				Venues.put_on(dug, Venues.box(Vector3(0.15, 1.6, 1.6)), Venues.paint(Color("2b2f3a"), 0.6), Vector3(x, 0.8, 0))

		# the team
		_pitcher = Venues.npc(root, Vector3(0, 1.15, -4.5), Color("f4f1ea"), {hat = "cap", accent = "red", outfit = "stripes"}, 0.9)
		_batter = Venues.npc(root, Vector3(0.9, 0.85, 0.2), Color("2f6bff"), {hat = "cap", accent = "blue", outfit = "plain"}, 0.9)
		_batter.rotation.y = PI * 0.5
		_pitcher.rotation.y = PI
		var catcher := Venues.npc(root, Vector3(0, 0.75, 1.1), Color("f4f1ea"), {hat = "cap", accent = "black"}, 0.8)
		_fielders = [catcher]
		var field := [Vector3(-7, 0.85, -12), Vector3(0, 0.85, -15), Vector3(7, 0.85, -12), Vector3(5.5, 0.85, -6), Vector3(-5.5, 0.85, -6)]
		for p in field.slice(0, 2 if Look.fast() else 5):  # each local is a dozen draw calls: phones get a smaller team
			var f := Venues.npc(root, p, Color("f4f1ea"), {hat = "cap", accent = "red", outfit = "stripes"}, 0.85)
			f.rotation.y = PI
			_fielders.append(f)
		_bat = live(Node3D.new())
		_bat.position = Vector3(0.9, 1.4, 0.2)
		root.add_child(_bat)
		var stick := MeshInstance3D.new()
		stick.mesh = Venues.cyl(0.07, 0.04, 1.1, 8)
		stick.material_override = Venues.paint(Color("c08a4a"), 0.5)
		stick.position = Vector3(0, 0.0, -0.55)
		stick.rotation.x = PI * 0.5
		_bat.add_child(stick)
		_ball = live(Venues.put_on(root, Venues.ball(0.1), Venues.ball_mat(3), Vector3.ZERO))
		var giant := Vector2(-31, 31)
		put(Venues.cyl(1.2, 1.5, 1.2, 16), Venues.paint(Color("d7d0c0"), 0.8), at(giant.x, giant.y, 0.6))
		put(Venues.ball(1.5), Venues.ball_mat(3), at(giant.x, giant.y, 2.7), Vector3(0.4, 0.8, 0.2))
		park.take(giant, 2.5)

	func _fan(r: float, dy: float) -> ArrayMesh:
		## The infield dirt: a quarter circle out from home plate.
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var seg := 20
		for k in seg:
			var a0 := -PI * 0.25 + PI * 0.5 * k / seg
			var a1 := -PI * 0.25 + PI * 0.5 * (k + 1) / seg
			st.set_normal(Vector3.UP)
			for v in [Vector3(0, dy, 1.5), Vector3(sin(a0) * r, dy, -cos(a0) * r), Vector3(sin(a1) * r, dy, -cos(a1) * r)]:
				st.add_vertex(v)
		return st.commit()

	func _process(dt: float) -> void:
		_t += dt
		var cycle := fmod(_t, 5.0)
		_pitcher.pose(dt, {punch = [clampf(1.0 - absf(cycle - 1.2) * 3.0, 0.0, 1.0), 0.0]})
		_batter.pose(dt, {})
		for f in _fielders:
			(f as BowlerModel).pose(dt, {})
		var swing := clampf((cycle - 1.85) / 0.25, 0.0, 1.0)
		_bat.rotation.y = lerpf(0.4, -2.6, swing)
		if cycle < 1.3:
			_ball.position = Vector3(0, 1.6, -4.5)
			_hit = fmod(_t, 15.0) < 5.0
		elif cycle < 2.0:
			_ball.position = Vector3(0, 1.6, -4.5).lerp(Vector3(0.2, 1.1, 0.6), (cycle - 1.3) / 0.7)
		elif _hit:
			var f := clampf((cycle - 2.0) / 2.0, 0.0, 1.0)
			_ball.position = Vector3(0, 1.1, 0).lerp(Vector3(-6, 0.3, -17), f) + Vector3(0, sin(PI * f) * 10.0, 0)
		else:
			_ball.position = Vector3(0.2, 1.1, 1.2)

	func plate() -> Vector3:
		return at(HOME.x, HOME.y, 1.5)

	func swing() -> void:
		_t = 1.7  # straight to the swing


# ================================================================ the courts

class Courts extends Venue:
	## A basketball court and a tennis court by the start, and a skatepark: players playing, a skater skating.
	const HOOP := Vector2(16, 31)
	const TENNIS := Vector2(28, 21)
	const SKATE := Vector2(-17, 28)
	var _dribbler: BowlerModel
	var _bball: MeshInstance3D
	var _tennis := []
	var _tball: MeshInstance3D
	var _skater: Node3D
	var _dunk := -1.0

	func make() -> void:
		id = "courts"
		var y := park.ground(HOOP.x, HOOP.y)
		# basketball
		var court := ShaderMaterial.new()
		court.shader = Shader.new()
		court.shader.code = """
shader_type spatial;
uniform vec2 size = vec2(15.0, 9.0);
float band(float d) { return 1.0 - smoothstep(0.05, 0.08, abs(d)); }
void fragment() {
	vec2 p = (UV - 0.5) * size;
	vec3 c = mix(vec3(0.85, 0.48, 0.22), vec3(0.2, 0.36, 0.75), step(size.x * 0.5 - 0.6, abs(p.x)) + step(size.y * 0.5 - 0.6, abs(p.y)));
	float l = band(abs(p.x) - (size.x * 0.5 - 0.6)) * step(abs(p.y), size.y * 0.5 - 0.6) + band(abs(p.y) - (size.y * 0.5 - 0.6)) * step(abs(p.x), size.x * 0.5 - 0.6);
	l += band(p.x) * step(abs(p.y), size.y * 0.5 - 0.6) + band(length(p) - 1.6);
	float q = size.x * 0.5 - 0.6 - abs(p.x);
	l += band(length(vec2(q, p.y)) - 5.0) * step(0.0, q) * step(abs(p.y), 4.0);
	vec3 key = vec3(0.86, 0.22, 0.2);
	c = mix(c, key, step(q, 4.0) * step(0.0, q) * step(abs(p.y), 1.6));
	ALBEDO = mix(c, vec3(0.98), clamp(l, 0.0, 1.0));
	ROUGHNESS = 0.5;
}
"""
		var pm := PlaneMesh.new()
		pm.size = Vector2(15, 9)
		put(pm, court, Vector3(HOOP.x, y + 0.04, HOOP.y))
		park.take(HOOP, 8.5)
		for s in [-1.0, 1.0]:
			var base := Vector3(HOOP.x + s * 7.6, y, HOOP.y)
			put(Venues.cyl(0.1, 0.12, 3.6, 8), Venues.paint(Color("3a3f4a"), 0.4, 0.6), base + Vector3(s * 0.5, 1.8, 0))
			put(Venues.box(Vector3(0.1, 1.1, 1.8)), Venues.paint(Color("fafafa"), 0.3), base + Vector3(0, 3.3, 0))
			var rim := TorusMesh.new()
			rim.inner_radius = 0.22
			rim.outer_radius = 0.26
			put(rim, Venues.paint(Color("ff6a00"), 0.4, 0.5), base + Vector3(-s * 0.35, 3.0, 0))
		_dribbler = Venues.npc(self, Vector3(HOOP.x - 2.0, y + 0.9, HOOP.y + 1.0), Color("ff8c2a"), {hat = "headband", outfit = "plain", accent = "white"}, 0.95)
		_bball = live(put(Venues.ball(0.16), Venues.ball_mat(1), Vector3.ZERO))
		# tennis
		var tennis := ShaderMaterial.new()
		tennis.shader = Shader.new()
		tennis.shader.code = """
shader_type spatial;
uniform vec2 size = vec2(15.0, 8.5);
float band(float d) { return 1.0 - smoothstep(0.04, 0.07, abs(d)); }
void fragment() {
	vec2 p = (UV - 0.5) * size;
	vec2 h = vec2(size.x * 0.5 - 1.2, size.y * 0.5 - 0.8);
	vec3 c = mix(vec3(0.24, 0.52, 0.36), vec3(0.22, 0.42, 0.72), step(abs(p.x), h.x) * step(abs(p.y), h.y));
	float l = band(abs(p.x) - h.x) * step(abs(p.y), h.y) + band(abs(p.y) - h.y) * step(abs(p.x), h.x);
	l += band(abs(p.y) - h.y * 0.75) * step(abs(p.x), h.x);
	l += band(abs(p.x) - h.x * 0.55) * step(abs(p.y), h.y * 0.75);
	l += band(p.y) * step(abs(p.x), h.x * 0.55);
	ALBEDO = mix(c, vec3(0.98), clamp(l, 0.0, 1.0));
	ROUGHNESS = 0.6;
}
"""
		var tm := PlaneMesh.new()
		tm.size = Vector2(15, 8.5)
		var ty := park.ground(TENNIS.x, TENNIS.y)
		put(tm, tennis, Vector3(TENNIS.x, ty + 0.04, TENNIS.y))
		var tnet := StandardMaterial3D.new()
		tnet.albedo_color = Color(0.1, 0.1, 0.12, 0.6)
		tnet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tnet.cull_mode = BaseMaterial3D.CULL_DISABLED
		put(Venues.box(Vector3(0.03, 0.9, 7.6)), tnet, Vector3(TENNIS.x, ty + 0.5, TENNIS.y))
		put(Venues.box(Vector3(0.05, 0.06, 7.6)), Venues.paint(Color.WHITE), Vector3(TENNIS.x, ty + 0.95, TENNIS.y))
		park.take(TENNIS, 9.0)
		for s in [-1.0, 1.0]:
			var tp := Venues.npc(self, Vector3(TENNIS.x + s * 5.4, ty + 0.9, TENNIS.y), [Color("2ecc71"), Color("9b59ff")][int(s > 0)],
				{hat = "headband", outfit = "plain", accent = "white"}, 0.9)
			tp.rotation.y = -s * PI * 0.5
			_tennis.append(tp)
		_tball = live(put(Venues.ball(0.12), Venues.ball_mat(2), Vector3.ZERO))
		var tb := Vector2(38.5, 14.5)
		put(Venues.cyl(0.9, 1.1, 0.8, 16), Venues.paint(Color("d7d0c0"), 0.8), at(tb.x, tb.y, 0.4))
		put(Venues.ball(1.2), Venues.ball_mat(2), at(tb.x, tb.y, 2.0), Vector3(0.3, 0.5, 0))
		park.take(tb, 2.0)
		var bb := Vector2(6.5, 24.5)
		put(Venues.cyl(0.9, 1.1, 0.8, 16), Venues.paint(Color("d7d0c0"), 0.8), at(bb.x, bb.y, 0.4))
		put(Venues.ball(1.3), Venues.ball_mat(1), at(bb.x, bb.y, 2.1), Vector3(0.2, 0.9, 0.1))
		park.take(bb, 2.0)
		# the skatepark
		var sy := park.ground(SKATE.x, SKATE.y)
		put(Venues.box(Vector3(12.0, 0.1, 9.0)), Venues.paint(Color("b9bcc4"), 0.9), Vector3(SKATE.x, sy + 0.03, SKATE.y))
		Venues.prop(self, "skate/half-pipe", Vector3(SKATE.x - 3.0, sy, SKATE.y - 2.0), 90.0, 3.0)
		Venues.prop(self, "skate/half-pipe", Vector3(SKATE.x - 3.0, sy, SKATE.y + 1.0), -90.0, 3.0)
		Venues.prop(self, "skate/ramp", Vector3(SKATE.x + 3.5, sy, SKATE.y - 2.5), 0.0, 3.0)
		Venues.prop(self, "skate/rail-high", Vector3(SKATE.x + 3.5, sy, SKATE.y + 1.5), 90.0, 3.0)
		Venues.prop(self, "skate/obstacle-box-grind", Vector3(SKATE.x + 0.5, sy, SKATE.y + 2.5), 90.0, 3.0)
		Venues.prop(self, "skate/benches", Vector3(SKATE.x + 5.5, sy, SKATE.y + 3.5), 180.0, 2.0)
		_skater = Venues.prop(self, "skate/character-skate-boy", Vector3(SKATE.x, sy, SKATE.y), 0.0, 2.4)
		park.take(SKATE, 7.5)

	func _process(dt: float) -> void:
		var t := Time.get_ticks_msec() * 0.001
		var y := park.ground(HOOP.x, HOOP.y)
		if _dunk >= 0.0:
			_dunk += dt
			var f := clampf(_dunk / 1.4, 0.0, 1.0)
			var rimp := Vector3(HOOP.x + 7.25, y + 3.0, HOOP.y)
			var from := Vector3(HOOP.x + 2.0, y + 0.9, HOOP.y)
			_dribbler.position = from.lerp(rimp + Vector3(-0.4, -1.0, 0), f) + Vector3(0, sin(PI * f) * 1.2, 0)
			_bball.position = _dribbler.position + Vector3(0.3, 1.2, 0) if f < 0.85 else rimp + Vector3(0, -0.9 * (f - 0.85) / 0.15, 0)
			_dribbler.pose(dt, {dance = f > 0.85, speed = 4.0})
			if _dunk > 2.6:
				_dunk = -1.0
		else:
			var x := HOOP.x + sin(t * 0.7) * 3.0
			_dribbler.position = Vector3(x, y + 0.9, HOOP.y + 1.0)
			_dribbler.rotation.y = PI * 0.5 if cos(t * 0.7) > 0.0 else -PI * 0.5
			_dribbler.pose(dt, {speed = 2.5})
			_bball.position = Vector3(x + 0.35, y + 0.2 + absf(sin(t * 6.0)) * 0.9, HOOP.y + 1.3)
		for p in _tennis:
			(p as BowlerModel).pose(dt, {speed = 1.0})
		var ty := park.ground(TENNIS.x, TENNIS.y)
		var f := fmod(t * 0.6, 2.0)
		var ff := fmod(f, 1.0)
		var a := Vector3(TENNIS.x - 5.0, ty + 1.2, TENNIS.y)
		var b := Vector3(TENNIS.x + 5.0, ty + 1.2, TENNIS.y)
		_tball.position = (a.lerp(b, ff) if f < 1.0 else b.lerp(a, ff)) + Vector3(0, sin(PI * ff) * 2.2, 0)
		var sy := park.ground(SKATE.x, SKATE.y)
		var s := sin(t * 1.6)
		_skater.position = Vector3(SKATE.x - 3.0, sy + 0.2 + s * s * 1.6, SKATE.y - 0.5 + s * 2.6)
		_skater.rotation = Vector3(-s * 0.9, 0.0 if cos(t * 1.6) > 0.0 else PI, 0)

	func dunk() -> void:
		_dunk = 0.0

	func hoop() -> Vector3:
		return at(HOOP.x + 7.25, HOOP.y, 3.0)


# ================================================================ the plaza

class Plaza extends Venue:
	## Where the party starts: the gate from the pier, a paved square with a fountain, the giant trophy statue,
	## the Pro Shop, the ticket booth (the bank), the mascot's T-shirt cannon, lamps and food stands.
	var bank: Label3D
	var mascot: BowlerModel
	var _balloons := []
	var _cannon: Node3D

	func make() -> void:
		id = "plaza"
		var y := park.ground(0, 36)
		var paving := ShaderMaterial.new()
		paving.shader = Shader.new()
		paving.shader.code = """
shader_type spatial;
// Fan-pattern paving in two tones radiating from the plaza's centre.
void fragment() {
	vec2 p = (UV - 0.5) * 40.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float ring = floor(r / 1.2);
	float seg = floor(a / 6.2831 * (ring * 6.0 + 6.0));
	float tone = mod(ring + seg, 2.0);
	vec2 f = vec2(fract(r / 1.2), fract(a / 6.2831 * (ring * 6.0 + 6.0)));
	float mortar = smoothstep(0.0, 0.06, f.x) * smoothstep(0.0, 0.05, f.y);
	vec3 c = mix(vec3(0.90, 0.84, 0.72), vec3(0.80, 0.70, 0.58), tone);
	c = mix(c * 0.7, c, mortar);
	c = mix(c, vec3(0.84, 0.44, 0.36), step(abs(r - 14.0), 0.5));
	ALBEDO = c;
	ROUGHNESS = 0.85;
	ALPHA = 1.0 - smoothstep(18.5, 20.0, r);
}
"""
		var pm := PlaneMesh.new()
		pm.size = Vector2(40, 40)
		var pav := put(pm, paving, Vector3(-4, y + 0.035, 36))
		pav.scale = Vector3(1.0, 1.0, 0.62)
		pav.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		paving.render_priority = -1
		_fountain(Vector2(-8, 33), y)
		_statue(Vector2(9, 30), y)
		_shop(Vector2(14, 35.5), y)
		_booth(Vector2(9.0, 47.0), y)
		_gate(Vector2(0, 50.0), y)
		_cannon_booth(Vector2(-11, 47.5))
		var lamp := "racing/lightPostModern"
		for p in [Vector2(-6, 39), Vector2(6, 39), Vector2(-16, 39.5), Vector2(19, 38), Vector2(-24, 39.5), Vector2(26, 44), Vector2(-4, 22), Vector2(6, 22)]:
			Venues.prop(self, lamp, at(p.x, p.y), 0.0, 5.0)
			park.take(p, 0.8)
		for p in [Vector2(-22, 34), Vector2(-28, 36)]:  # food stands
			Venues.prop(self, "racing/tent", at(p.x, p.y), 30.0, 3.4)
			park.take(p, 2.5)
		for p in [Vector2(-3, 30), Vector2(-14, 38)]:
			Venues.prop(self, "holiday/bench", at(p.x, p.y), 0.0, 1.8)
		park.take(Vector2(-4, 36), 9.0)

	func _fountain(p: Vector2, y: float) -> void:
		var stone := Venues.paint(Color("e3d8c3"), 0.7)
		var water := Venues.paint(Color("4fb8e8"), 0.05)
		water.metallic_specular = 0.9
		put(Venues.cyl(3.4, 3.6, 0.7, 40), stone, Vector3(p.x, y + 0.35, p.y))
		put(Venues.cyl(3.0, 3.0, 0.1, 40), water, Vector3(p.x, y + 0.66, p.y))
		put(Venues.cyl(0.35, 0.45, 2.4, 16), stone, Vector3(p.x, y + 1.6, p.y))
		put(Venues.cyl(1.4, 0.5, 0.4, 24), stone, Vector3(p.x, y + 2.8, p.y))
		put(Venues.ball(0.9), Venues.ball_mat(0), Vector3(p.x, y + 3.85, p.y))
		park.take(p, 4.0)
		if Look.fast():
			return
		var spray := CPUParticles3D.new()
		spray.mesh = Venues.ball(0.07)
		spray.material_override = Venues.paint(Color("c9ecff"), 0.1)
		spray.amount = 60
		spray.lifetime = 1.1
		spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
		spray.emission_ring_radius = 1.3
		spray.emission_ring_inner_radius = 1.2
		spray.emission_ring_height = 0.0
		spray.emission_ring_axis = Vector3.UP
		spray.direction = Vector3.UP
		spray.spread = 25.0
		spray.initial_velocity_min = 3.0
		spray.initial_velocity_max = 3.6
		spray.position = Vector3(p.x, y + 3.0, p.y)
		add_child(spray)

	func _statue(p: Vector2, y: float) -> void:
		## A giant golden trophy on a marble plinth.
		put(Venues.box(Vector3(3.2, 1.6, 3.2)), Venues.paint(Color("efe9df"), 0.3), Vector3(p.x, y + 0.8, p.y))
		put(Venues.box(Vector3(2.6, 0.5, 2.6)), Venues.paint(Color("2b2f3a"), 0.4), Vector3(p.x, y + 1.85, p.y))
		var gold := StandardMaterial3D.new()
		gold.albedo_color = Color("ffc93c")
		gold.metallic = 1.0
		gold.roughness = 0.22
		var cup := put(Park.lathe([Vector2(0, 0), Vector2(0.55, 0), Vector2(0.55, 0.12), Vector2(0.16, 0.38), Vector2(0.11, 0.62), Vector2(0.36, 0.9),
			Vector2(0.6, 1.15), Vector2(0.7, 1.62), Vector2(0.62, 1.62), Vector2(0, 1.1)], 32), gold, Vector3(p.x, y + 2.1, p.y))
		cup.scale = Vector3.ONE * 2.2
		var l := Venues.label(self, "CHAMPIONS", Vector3(p.x, y + 0.9, p.y + 1.62), 56, Color("2b2f3a"), Color(0, 0, 0, 0))
		l.pixel_size = 0.008
		park.take(p, 3.0)

	func _shop(p: Vector2, y: float) -> void:
		## The Pro Shop: a striped awning over a shop window.
		put(Venues.box(Vector3(7.0, 3.6, 4.5)), Venues.paint(Color("f6f1e4"), 0.7), Vector3(p.x, y + 1.8, p.y))
		put(Venues.box(Vector3(7.4, 0.4, 4.9)), Venues.paint(Color("0b8a80"), 0.5), Vector3(p.x, y + 3.8, p.y))
		for k in 7:
			var stripe := put(Venues.box(Vector3(1.0, 0.08, 1.8)), Venues.paint(Color("e8323c") if k % 2 == 0 else Color("fafafa"), 0.6),
				Vector3(p.x - 3.0 + k, y + 2.9, p.y + 3.0))
			stripe.rotation.x = 0.35
		put(Venues.box(Vector3(5.0, 1.8, 0.1)), Venues.glow(Color("bfe6ff"), 0.5), Vector3(p.x, y + 1.6, p.y + 2.27))
		var l := Venues.label(self, "PRO SHOP", Vector3(p.x, y + 4.7, p.y + 2.3), 110, Color.WHITE, Color("0b8a80"))
		l.pixel_size = 0.011
		park.take(p, 5.0)

	func _booth(p: Vector2, y: float) -> void:
		## The ticket booth: passing it puts coins in the bank, landing on its space wins the lot.
		put(Venues.box(Vector3(2.6, 2.6, 2.2)), Venues.paint(Color("ffd23f"), 0.5), Vector3(p.x, y + 1.3, p.y))
		put(Venues.box(Vector3(1.8, 1.0, 0.1)), Venues.glow(Color("bfe6ff"), 0.4), Vector3(p.x, y + 1.6, p.y - 1.12))
		var roof := put(Venues.cyl(0.0, 2.2, 1.3, 4), Venues.paint(Color("e8323c"), 0.5), Vector3(p.x, y + 3.25, p.y), Vector3(0, PI * 0.25, 0))
		roof.scale = Vector3(1, 1, 0.9)
		bank = Venues.label(self, "BANK\n0", Vector3(p.x, y + 4.4, p.y), 64, Color("ffd23f"), Color("2b2f3a"))
		bank.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		park.take(p, 2.2)

	func _gate(p: Vector2, y: float) -> void:
		## The way in from the pier: two striped towers, the park's name across the top, balloons.
		var red := Venues.paint(Color("e8323c"), 0.5)
		var cream := Venues.paint(Color("fff4df"), 0.5)
		for x in [-6.0, 6.0]:
			for k in 7:
				put(Venues.cyl(0.65, 0.65, 1.0, 20), red if k % 2 == 0 else cream, Vector3(p.x + x, y + 0.5 + k, p.y))
			put(Venues.cyl(0.0, 0.95, 1.6, 20), Venues.paint(Color("2f6bff"), 0.4), Vector3(p.x + x, y + 7.8, p.y))
		put(Venues.box(Vector3(12.4, 1.5, 0.8)), Venues.paint(Color("2f6bff"), 0.4), Vector3(p.x, y + 6.4, p.y))
		var l := Venues.label(self, "PARTY PARK", Vector3(p.x, y + 6.42, p.y - 0.45), 150, Color.WHITE, Color("e8323c"))
		l.rotation.y = PI
		var l2 := Venues.label(self, "PARTY PARK", Vector3(p.x, y + 6.42, p.y + 0.45), 150, Color.WHITE, Color("e8323c"))
		l2.pixel_size = 0.01
		l.pixel_size = 0.01
		var cols := [Color("e8323c"), Color("ffd23f"), Color("2ecc71"), Color("2f6bff"), Color("ff5fb4")]
		for s in [-1.0, 1.0]:
			for k in 6:
				var b := put(Venues.ball(0.5), Venues.paint(cols[(k + int(s > 0)) % cols.size()], 0.2),
					Vector3(p.x + s * (6.9 + sin(k * 2.1) * 0.6), y + 8.4 + (k % 3) * 0.6, p.y + cos(k * 1.7) * 0.6))
				b.scale = Vector3(1, 1.2, 1)
				_balloons.append(live(b))
		# the pier down to the water, with the ferry
		var plank := Venues.paint(Color("b98a5a"), 0.85)
		put(Venues.box(Vector3(5.0, 0.3, 16.0)), plank, Vector3(p.x, 0.8, p.y + 9.0))
		for k in 6:
			for s in [-2.2, 2.2]:
				put(Venues.cyl(0.18, 0.18, 3.0, 6), plank, Vector3(p.x + s, -0.6, p.y + 3.0 + k * 2.8))
		park.take(Vector2(p.x, p.y + 4.0), 9.0)
		var ferry := Node3D.new()
		ferry.position = Vector3(p.x + 6.5, Park.SEA, p.y + 13.0)
		add_child(ferry)
		Venues.put_on(ferry, Venues.box(Vector3(5.0, 1.6, 12.0)), Venues.paint(Color("fafafa"), 0.4), Vector3(0, 0.4, 0))
		Venues.put_on(ferry, Venues.box(Vector3(4.0, 1.6, 6.0)), Venues.paint(Color("2f6bff"), 0.4), Vector3(0, 2.0, 1.0))
		Venues.put_on(ferry, Venues.cyl(0.5, 0.5, 2.0, 12), Venues.paint(Color("e8323c"), 0.4), Vector3(0, 3.6, 2.0))
		park.take(p, 2.0)

	func _cannon_booth(p: Vector2) -> void:
		## The mascot (a big orange fella) with a T-shirt cannon.
		var y := park.ground(p.x, p.y)
		mascot = Venues.npc(self, Vector3(p.x, y + 1.5, p.y), Color("ff8c2a"), {hat = "party", eyes = "googly", mouth = "grin", outfit = "polka", accent = "yellow"}, 1.7)
		mascot.rotation.y = PI
		_cannon = live(Node3D.new())
		_cannon.position = Vector3(p.x + 1.3, y + 1.6, p.y - 0.4)
		add_child(_cannon)
		var tube := MeshInstance3D.new()
		tube.mesh = Venues.cyl(0.22, 0.26, 1.6, 12)
		tube.material_override = Venues.paint(Color("3a3f4a"), 0.4, 0.6)
		tube.rotation.x = -PI * 0.3
		_cannon.add_child(tube)
		park.take(p, 2.5)

	func _process(dt: float) -> void:
		var t := Time.get_ticks_msec() * 0.001
		for k in _balloons.size():
			_balloons[k].position.y += cos(t * 1.5 + k) * 0.25 * dt
		mascot.pose(dt, {dance = true})

	func cannon(target: Vector3) -> void:
		## Fire a prize at someone.
		var gift := put(Venues.box(Vector3(0.6, 0.6, 0.6)), Venues.paint(Color("ffd23f"), 0.4), _cannon.global_position)
		var from := _cannon.global_position + Vector3(0, 0.8, -0.6)
		var tw := gift.create_tween()
		tw.tween_method(func(f: float):
			gift.global_position = from.lerp(target + Vector3(0, 1.2, 0), f) + Vector3(0, sin(PI * f) * 9.0, 0)
			gift.rotation = Vector3(f * 9.0, f * 7.0, 0), 0.0, 1.0, 1.4)
		tw.tween_callback(gift.queue_free)


# ================================================================ the alley and the dojo

class Alley extends Venue:
	## The bowling alley (where the bowling minigames happen): a retro hall with a giant pin and ball on the roof.
	const C := Vector2(-52, -24)

	func make() -> void:
		id = "bowling"
		var y := park.ground(C.x, C.y)
		park.take(C, 9.0)
		var root := Node3D.new()
		root.position = Vector3(C.x, y, C.y)
		root.rotation.y = PI * 0.5  # its front faces east, onto the path
		add_child(root)
		Venues.put_on(root, Venues.box(Vector3(12.0, 5.0, 9.0)), Venues.paint(Color("f6f1e4"), 0.6), Vector3(0, 2.5, 0))
		Venues.put_on(root, Venues.box(Vector3(12.4, 0.9, 9.4)), Venues.paint(Color("6b4fa0"), 0.5), Vector3(0, 5.2, 0))
		Venues.put_on(root, Venues.box(Vector3(12.1, 0.5, 0.1)), Venues.glow(Color("ff5fb4"), 2.0), Vector3(0, 4.3, 4.52))
		Venues.put_on(root, Venues.box(Vector3(5.0, 2.6, 0.1)), Venues.glow(Color("8fd3ff"), 0.6), Vector3(0, 1.4, 4.52))
		var l := Venues.label(root, "BOWLING", Vector3(0, 3.4, 4.6), 140, Color("ffd23f"), Color("6b4fa0"))
		l.pixel_size = 0.011
		var pin := Venues.put_on(root, Arena.pin_mesh(), Arena.pin_material(), Vector3(-2.5, 5.6, 0))
		pin.scale = Vector3.ONE * 4.0
		var ball := Venues.put_on(root, Venues.ball(1.4), Venues.paint(Color("e5383b"), 0.08), Vector3(2.8, 7.0, 0))
		ball.material_override.metallic_specular = 1.0
		# a striped awning over the doors, round windows down the sides, and a car park
		Venues.put_on(root, Venues.box(Vector3(6.0, 0.25, 2.2)), Venues.paint(Color("ffd23f"), 0.5), Vector3(0, 3.1, 5.6))
		for x in [-2.8, 2.8]:
			Venues.put_on(root, Venues.cyl(0.08, 0.08, 3.1, 8), Venues.paint(Color("e9e2d2"), 0.4, 0.5), Vector3(x, 1.55, 6.5))
		for side in [-1.0, 1.0]:
			for k in 4:
				var win := Venues.put_on(root, Venues.cyl(0.55, 0.55, 0.1, 20), Venues.glow(Color("8fd3ff"), 0.4), Vector3(-4.0 + k * 2.6, 2.6, side * 4.52))
				win.rotation.x = PI * 0.5
		Venues.put_on(root, Venues.box(Vector3(12.1, 0.6, 9.1)), Venues.paint(Color("1fd1c1"), 0.6), Vector3(0, 0.3, 0))
		for k in 3:
			Venues.prop(self, ["cars/sedan", "cars/van", "cars/hatchback-sports"][k], at(C.x - 5.0 + k * 3.0, C.y + 9.5), 0.0, 1.3)


class Dojo extends Venue:
	## The sumo dojo (where Sumo happens): a raised clay ring under a hanging roof, banners round it.
	const C := Vector2(62, -13)

	func make() -> void:
		id = "dojo"
		var y := park.ground(C.x, C.y)
		park.take(C, 6.0)
		put(Venues.box(Vector3(8.0, 1.0, 8.0)), Venues.paint(Color("b5793f"), 0.9), Vector3(C.x, y + 0.5, C.y))
		var rope := TorusMesh.new()
		rope.inner_radius = 2.8
		rope.outer_radius = 3.05
		put(rope, Venues.paint(Color("e6cf8a"), 0.85), Vector3(C.x, y + 1.02, C.y), Vector3.ZERO, Vector3(1, 0.4, 1))
		var tassels := [Color("2a8f5a"), Color("e5383b"), Color("f2f2f2"), Color("1f2a44")]
		for k in 4:
			var c := Vector3(cos(PI * 0.25 + PI * 0.5 * k), 0, sin(PI * 0.25 + PI * 0.5 * k)) * 4.8
			put(Venues.cyl(0.15, 0.18, 6.0, 8), Venues.paint(Color("8a5a36"), 0.6), Vector3(C.x, y + 3.0, C.y) + c)
			put(Venues.ball(0.45), Venues.paint(tassels[k], 0.6), Vector3(C.x, y + 5.4, C.y) + c)
		var roof := put(Venues.cyl(0.6, 6.4, 2.0, 4), Venues.paint(Color("5a3a20"), 0.6), Vector3(C.x, y + 7.0, C.y), Vector3(0, PI * 0.25, 0))
		roof.scale = Vector3(1, 1, 1)
		var l := Venues.label(self, "SUMO", Vector3(C.x, y + 9.0, C.y), 150, Color.WHITE, Color("b33a2e"))
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		for k in 6:  # nobori banners
			var a := TAU * k / 6.0
			var p := Vector3(C.x + cos(a) * 6.5, y, C.y + sin(a) * 6.5)
			put(Venues.cyl(0.05, 0.05, 4.0, 6), Venues.paint(Color("2b2f3a")), p + Vector3(0, 2.0, 0))
			put(Venues.box(Vector3(0.05, 2.6, 0.8)), Venues.paint([Color("e8323c"), Color("2f6bff"), Color("ffd23f")][k % 3], 0.7), p + Vector3(0, 2.6, 0.42))


# ================================================================ overhead

class Skies extends Venue:
	## A blimp circling the park and hot-air balloons drifting by.
	var _blimp: Node3D
	var _balloons := []

	func make() -> void:
		id = "skies"
		_blimp = Node3D.new()
		add_child(_blimp)
		var body := MeshInstance3D.new()
		body.mesh = Venues.ball(1.0)
		body.material_override = Venues.paint(Color("f4f1ea"), 0.4)
		body.scale = Vector3(3.2, 3.2, 10.0)
		_blimp.add_child(body)
		for s in [-1.0, 1.0]:
			var fin := MeshInstance3D.new()
			fin.mesh = Venues.box(Vector3(0.2, 3.0, 2.2))
			fin.material_override = Venues.paint(Color("e8323c"), 0.5)
			fin.position = Vector3(s * 1.4, 0, 8.4)
			fin.rotation.z = s * 0.6
			_blimp.add_child(fin)
			var l := Label3D.new()
			l.text = "PARTY PARK"
			l.font = Look.title_font()
			l.font_size = 160
			l.outline_size = 20
			l.modulate = Color("2f6bff")
			l.outline_modulate = Color.WHITE
			l.pixel_size = 0.011
			l.position = Vector3(s * 3.25, 0.3, 0)
			l.rotation.y = s * PI * 0.5
			_blimp.add_child(l)
		var gondola := MeshInstance3D.new()
		gondola.mesh = Venues.box(Vector3(1.2, 0.8, 3.0))
		gondola.material_override = Venues.paint(Color("2b2f3a"), 0.5)
		gondola.position.y = -3.4
		_blimp.add_child(gondola)
		var cols := [[Color("e8323c"), Color("ffd23f")], [Color("2f6bff"), Color("fafafa")], [Color("2ecc71"), Color("ff8c2a")]]
		for k in 3:
			var b := Node3D.new()
			add_child(b)
			for s in 8:
				var gore := MeshInstance3D.new()
				gore.mesh = Venues.ball(4.0)
				gore.material_override = Venues.paint(cols[k][s % 2], 0.5)
				gore.scale = Vector3(0.38, 1.15, 1.0)
				gore.rotation.y = TAU * s / 16.0
				b.add_child(gore)
			var basket := MeshInstance3D.new()
			basket.mesh = Venues.box(Vector3(1.4, 1.0, 1.4))
			basket.material_override = Venues.paint(Color("8a5634"), 0.8)
			basket.position.y = -6.0
			b.add_child(basket)
			_balloons.append([b, k])

	func _process(_dt: float) -> void:
		var t := Time.get_ticks_msec() * 0.001
		var a := t * 0.05
		_blimp.position = Vector3(cos(a) * 85.0, 48.0 + sin(t * 0.3) * 1.5, -10.0 + sin(a) * 70.0)
		_blimp.rotation.y = -a + PI
		for b in _balloons:
			var k: int = b[1]
			var bb: Node3D = b[0]
			bb.position = Vector3(-120.0 + fmod(t * 1.2 + k * 90.0, 260.0), 55.0 + k * 9.0 + sin(t * 0.2 + k) * 3.0, -80.0 + k * 35.0)


# ================================================================ shared builders

static func paint(c: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	## A plain painted surface (shared: one material per colour and finish).
	var key := "%s/%s/%s" % [c.to_html(), rough, metal]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		if c.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mats[key] = m
	return _mats[key]


static func glow(c: Color, energy := 1.0) -> StandardMaterial3D:
	var key := "glow/%s/%s" % [c.to_html(), energy]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
		_mats[key] = m
	return _mats[key]


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func cyl(top: float, bottom: float, h: float, seg := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func ball(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 32
	s.rings = 16
	return s


static func put_on(parent: Node, m: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func label(parent: Node, text: String, pos: Vector3, size: int, fill: Color, ink: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Look.title_font()
	l.font_size = size
	l.outline_size = size / 6
	l.modulate = fill
	l.outline_modulate = ink
	l.pixel_size = 0.01
	l.position = pos
	parent.add_child(l)
	return l


static func prop(parent: Node3D, path: String, pos: Vector3, yaw_deg := 0.0, s := 1.0) -> Node3D:
	## A Kenney model standing centred on pos (some kits put their origin off in a corner).
	var full := "res://assets/props/%s.glb" % path
	var scene: PackedScene = load(full)
	var n: Node3D = scene.instantiate()
	if not _offsets.has(path):
		var box := AABB()
		var first := true
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			var xf := Transform3D.IDENTITY
			var p: Node = mi
			while p != n:
				xf = (p as Node3D).transform * xf
				p = p.get_parent()
			box = xf * mi.get_aabb() if first else box.merge(xf * mi.get_aabb())
			first = false
		var c := box.get_center()
		_offsets[path] = Vector3(-c.x, -box.position.y, -c.z)
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		for sidx in mi.mesh.get_surface_count():
			var m = mi.mesh.surface_get_material(sidx)
			if m is BaseMaterial3D and m.albedo_texture == null:
				mi.set_surface_override_material(sidx, punch(m))
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation_degrees.y = yaw_deg
	holder.scale = Vector3.ONE * s
	parent.add_child(holder)
	n.position = _offsets[path]
	holder.add_child(n)
	return holder


static func punch(m: BaseMaterial3D) -> BaseMaterial3D:
	## Kenney's flat colours are pastel; under this sun they wash out. Richer, a touch darker.
	var key := "punch/%d" % m.get_instance_id()
	if not _mats.has(key):
		var d: BaseMaterial3D = m.duplicate()
		var c := d.albedo_color
		d.albedo_color = Color.from_hsv(c.h, minf(c.s * 1.7, 1.0), c.v * 0.9 if c.s > 0.12 else c.v * 0.86, c.a)
		_mats[key] = d
	return _mats[key]


static func npc(parent: Node, pos: Vector3, color: Color, skin: Dictionary, s := 1.0) -> BowlerModel:
	## One of the park's locals, built like a player.
	var m := BowlerModel.new()
	m.position = pos
	m.scale = Vector3.ONE * s * 0.8
	parent.add_child(m)
	m.build(color, skin)
	return m


static func gull(parent: Node) -> Node3D:
	var g := Node3D.new()
	g.set_meta("live", true)
	parent.add_child(g)
	var white := paint(Color("fbfbfb"), 0.5)
	var body := MeshInstance3D.new()
	body.mesh = ball(0.3)
	body.material_override = white
	body.scale = Vector3(0.8, 0.8, 1.6)
	g.add_child(body)
	for side in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		wing.mesh = box(Vector3(1.1, 0.05, 0.4))
		wing.material_override = white
		wing.position = Vector3(side * 0.6, 0.1, 0)
		wing.rotation.z = side * 0.35
		g.add_child(wing)
	var beak := MeshInstance3D.new()
	beak.mesh = box(Vector3(0.08, 0.08, 0.25))
	beak.material_override = paint(Color("ffb400"), 0.4)
	beak.position = Vector3(0, 0, -0.55)
	g.add_child(beak)
	return g


static func confetti(parent: Node3D, pos: Vector3, spread: float, col := Color(-1, 0, 0)) -> CPUParticles3D:
	## A one-shot burst (call restart()).
	var p := CPUParticles3D.new()
	p.mesh = box(Vector3(0.18, 0.02, 0.12))
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	p.material_override = m
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.85
	p.amount = 40 if Look.fast() else 160
	p.lifetime = 3.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(spread, 0.5, spread * 0.7)
	p.direction = Vector3.UP
	p.spread = 50.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector3(0, -4.0, 0)
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.damping_min = 1.0
	p.damping_max = 2.0
	if col.r < 0.0:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
		g.colors = PackedColorArray([Color("e8323c"), Color("ffd23f"), Color("2f6bff"), Color("2ecc71"), Color("ff5fb4")])
		p.color_initial_ramp = g
	else:
		p.color = col
	p.position = pos
	parent.add_child(p)
	return p


static func ball_mat(kind: int) -> ShaderMaterial:
	## Sports balls: 0 football, 1 basketball, 2 tennis, 3 baseball, 4 beach ball, 5 golf, 6 volleyball.
	var key := "ball/%d" % kind
	if _mats.has(key):
		return _mats[key]
	if _ball_shader == null:
		_ball_shader = Shader.new()
		_ball_shader.code = """
shader_type spatial;
uniform int kind = 0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
float seam(vec3 p) {
	// the tennis / baseball seam: a curve wandering round the ball
	float a = atan(p.y, p.x);
	return abs(p.z - 0.55 * cos(2.0 * a) * sqrt(max(1.0 - p.z * p.z, 0.0)));
}
void fragment() {
	vec3 p = normalize(lp);
	vec3 c = vec3(1.0);
	float rough = 0.5;
	if (kind == 0) {
		float phi = 1.618034;
		vec3 ico[12] = vec3[](vec3(0, 1, phi), vec3(0, -1, phi), vec3(0, 1, -phi), vec3(0, -1, -phi), vec3(1, phi, 0), vec3(-1, phi, 0),
			vec3(1, -phi, 0), vec3(-1, -phi, 0), vec3(phi, 0, 1), vec3(-phi, 0, 1), vec3(phi, 0, -1), vec3(-phi, 0, -1));
		vec3 dod[8] = vec3[](vec3(1, 1, 1), vec3(1, 1, -1), vec3(1, -1, 1), vec3(1, -1, -1), vec3(-1, 1, 1), vec3(-1, 1, -1), vec3(-1, -1, 1), vec3(-1, -1, -1));
		float best = -2.0;
		float second = -2.0;
		bool pent = false;
		for (int i = 0; i < 12; i++) {
			float d = dot(p, normalize(ico[i]));
			if (d > best) { second = best; best = d; pent = true; } else if (d > second) { second = d; }
		}
		for (int i = 0; i < 8; i++) {
			float d = dot(p, normalize(dod[i]));
			if (d > best) { second = best; best = d; pent = false; } else if (d > second) { second = d; }
		}
		vec3 dodx[12] = vec3[](vec3(0, 1.0 / phi, phi), vec3(0, -1.0 / phi, phi), vec3(0, 1.0 / phi, -phi), vec3(0, -1.0 / phi, -phi),
			vec3(1.0 / phi, phi, 0), vec3(-1.0 / phi, phi, 0), vec3(1.0 / phi, -phi, 0), vec3(-1.0 / phi, -phi, 0),
			vec3(phi, 0, 1.0 / phi), vec3(-phi, 0, 1.0 / phi), vec3(phi, 0, -1.0 / phi), vec3(-phi, 0, -1.0 / phi));
		for (int i = 0; i < 12; i++) {
			float d = dot(p, normalize(dodx[i]));
			if (d > best) { second = best; best = d; pent = false; } else if (d > second) { second = d; }
		}
		c = pent ? vec3(0.08) : vec3(0.97);
		c *= smoothstep(0.004, 0.012, best - second) * 0.6 + 0.4;
		rough = 0.35;
	} else if (kind == 1) {
		c = vec3(0.86, 0.42, 0.12);
		float w = 0.022;
		float l = step(abs(p.x), w) + step(abs(p.y), w) + step(abs(abs(p.z) - 0.66 - 0.12 * p.y * p.y), w);
		c = mix(c, vec3(0.08), clamp(l, 0.0, 1.0));
		rough = 0.7;
	} else if (kind == 2) {
		c = mix(vec3(0.82, 0.92, 0.25), vec3(0.97), 1.0 - smoothstep(0.03, 0.05, seam(p)));
		rough = 0.95;
	} else if (kind == 3) {
		c = vec3(0.97, 0.96, 0.92);
		float s = seam(p);
		float stitch = (1.0 - smoothstep(0.02, 0.035, abs(s - 0.07))) * step(0.5, fract(atan(p.y, p.x) * 9.0));
		c = mix(c, vec3(0.85, 0.12, 0.12), stitch);
		rough = 0.6;
	} else if (kind == 4) {
		float a = atan(p.z, p.x) / 6.2831 + 0.5;
		vec3 cols[6] = vec3[](vec3(0.9, 0.15, 0.2), vec3(0.98), vec3(0.15, 0.4, 0.95), vec3(0.98, 0.85, 0.15), vec3(0.98), vec3(0.2, 0.8, 0.4));
		c = cols[int(floor(a * 6.0)) % 6];
		c = mix(c, vec3(0.98), step(0.9, abs(p.y)));
		rough = 0.25;
	} else if (kind == 5) {
		c = vec3(0.98);
		vec3 q = p * 24.0;
		float dimple = sin(q.x) * sin(q.y) * sin(q.z);
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(normalize(vec3(cos(q.x), cos(q.y), cos(q.z))) * dimple * 0.15, 0.0)).xyz);
		rough = 0.3;
	} else {
		float a = atan(p.z, p.x);
		float band = fract((a + p.y * 1.5) / 2.094);
		c = band < 0.33 ? vec3(0.98) : (band < 0.66 ? vec3(0.15, 0.4, 0.9) : vec3(0.98, 0.82, 0.15));
		rough = 0.5;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _ball_shader
	m.set_shader_parameter("kind", kind)
	_mats[key] = m
	return m
