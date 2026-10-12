class_name Board
extends Node3D
## The party board, drawn from Net.party on every peer: Party Park, an amusement park on an island. Its path winds past
## the rides, splits at two forks, and its landmarks hold the event spaces (the roller coaster, the prize wheel, the
## bowling alley and the sumo dojo). Everyone's bowler is a piece. The host also keeps time: bots' rolls, items and
## choices, timeouts, the beat after moving, and the minigame intro.

const ROLL_TIMEOUT := 15.0
const CHOOSE_TIMEOUT := 12.0
const INTRO := 4.0
const FINAL := 25.0  # then the host takes everyone back to the lobby
const OVERVIEW := Vector3(0, 40, 35)  # the camera watches the whole park from here
const OVERVIEW_LOOK := Vector3(0, 0, -0.5)
const EVENT := Color("ff7a1a")
const SPACE_COLORS := {S = Color("fff4df"), B = Color("3a86ff"), R = Color("e5383b"), L = Color("3ddc97"), I = Color("ffb400"),
	G = Color("6b4fa0"), K = Color("158f89"), D = EVENT, C = EVENT, P = EVENT, W = EVENT}
const SPACE_MARKS := {S = "GO", B = "+3", R = "-3", L = "?", I = "ITEM", G = "GULL", K = "BANK", D = "SUMO", C = "RIDE", P = "BOWL", W = "SPIN"}
const COASTER := [  # the roller coaster's track (x, height, z), starting at its station by the coaster space
	Vector3(12, 1.4, -15.5), Vector3(17, 1.4, -15.8), Vector3(21, 5.5, -16.5), Vector3(24, 9.0, -18.5), Vector3(26, 4.5, -21.5),
	Vector3(24, 1.6, -25), Vector3(18.5, 4.0, -26.2), Vector3(13, 7.5, -25), Vector3(8.5, 3.5, -22.5), Vector3(7, 2.0, -19),
	Vector3(8.5, 1.4, -16.2)]
const RIDE := 2.8  # seconds on the coaster, then a flying leap to the far side of the park

var _pieces := {}  # pid -> {root, model, dice, block, path: Array[Vector3], t, events, warp...}
var _star: Node3D
var _halo: Node3D
var _cam: Camera3D
var _cam_at := OVERVIEW
var _cam_look := OVERVIEW_LOOK
var _track := Curve3D.new()
var _car: Node3D
var _wheel: Node3D
var _gondolas: Array[Node3D] = []
var _carousel: Node3D
var _horses: Array[Node3D] = []
var _bank: Label3D
var _arrows := {}  # space -> bouncing arrow over it while you pick a way
var _bobbers: Array[Node3D] = []  # balloons
var _duck: Node3D
var _ui: Control
var _round: Label
var _sub: Label
var _news: Label
var _cards: VBoxContainer
var _roll: Button
var _items: HBoxContainer
var _fork: HBoxContainer
var _intro: PanelContainer
var _final: PanelContainer
var _phase := ""
var _host_t := 0.0
var _bot_at := {}
var _banked := false
var _news_seen := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	UI.use(false)  # a sunny island: the light palette
	_environment()
	_island()
	_paths()
	_landmarks()
	_greenery()
	_star_and_arrows()
	if Look.fast():
		Look.no_shadow(self)
	_hud()
	Net.party_changed.connect(_sync)
	Net.players_changed.connect(_sync)
	_sync()
	Music.play("menu")


# ---------------------------------------------------------------- state -> picture

func _sync() -> void:
	var s: Dictionary = Net.party
	if s.is_empty():
		return
	for pid in s.players:
		if Net.players.has(pid) and not _pieces.has(pid):
			_add_piece(pid)
	for pid in _pieces.keys():
		if not Net.players.has(pid):
			_pieces[pid].root.queue_free()
			_pieces.erase(pid)
	_star.position = Party.pos(s.star) + Vector3(0, 2.8, 0)
	_halo.position = Party.pos(s.star) + Vector3(0, 0.3, 0)
	_bank.text = "BANK\n%d" % s.bank
	if s.phase != _phase:
		_enter(s.phase, s)
	if s.phase == "roll":
		for pid in _pieces:  # items like a Swap Ticket move pieces before anyone rolls
			_place(pid, s)
			_pieces[pid].dice.text = str(s.rolls[pid]) if s.rolls.has(pid) else ("??" if s.doubled.has(pid) else "?")
	if _news_seen < s.news_n and not s.news.is_empty():  # the latest happening, across the top for a few seconds
		_news_seen = s.news_n
		var line: Array = s.news[-1]
		if Net.players.has(line[0]):
			_news.text = "%s %s%s" % [Net.players[line[0]].name, line[1], (" " + Net.players[line[2]].name) if Net.players.has(line[2]) else ""]
			UI.pop_in(_news)
			_news.create_tween().tween_property(_news, "modulate:a", 0.0, 0.6).set_delay(4.0)
	_refresh_hud(s)


func _enter(phase: String, s: Dictionary) -> void:
	_phase = phase
	_host_t = 0.0
	_bot_at.clear()
	_intro.visible = phase == "intro"
	_final.visible = phase == "final"
	match phase:
		"roll":
			for pid in _pieces:
				_place(pid, s)
				_pieces[pid].dice.visible = true
				_pieces[pid].block.visible = true
			Sfx.play_ui("beep")
		"move":
			for pid in s.moves:
				if _pieces.has(pid):
					var m: Dictionary = s.moves[pid]
					var p: Dictionary = _pieces[pid]
					p.path = m.path.map(func(i): return Party.pos(i))
					p.t = 0.0
					p.landed = false
					p.from = p.root.position - Vector3(0, 0.25, 0)
					p.events = m.events
					p.warp = m.get("warp", -1)
					p.warp_t = -1.0
					p.block.visible = false
					p.dice.text = str(m.path.size()) if not m.path.is_empty() else ""
		"intro":
			var g: Dictionary = Arena.maps()[s.next_game]
			_intro.get_node("V/Name").text = g.name
			_intro.get_node("V/Rules").text = g.rules
			UI.pop_in.call_deferred(_intro)
			Sfx.play_ui("go")
			for pid in _pieces:
				_pieces[pid].dice.visible = false
				_pieces[pid].block.visible = false
		"final":
			_show_final(s)


func _place(pid: int, s: Dictionary) -> void:
	## Pieces sharing a space stand in a little circle.
	var space: int = s.players[pid].space
	var here: Array = s.players.keys().filter(func(o): return s.players[o].space == space and _pieces.has(o))
	var i: int = here.find(pid)
	var r := 0.4 + 0.2 * here.size()  # a crowd on one space stands in a wider circle
	var off := Vector3.ZERO if here.size() == 1 else Vector3(cos(TAU * i / here.size()), 0, sin(TAU * i / here.size())) * r
	_pieces[pid].root.position = Party.pos(space) + off + Vector3(0, 0.25, 0)


func _process(dt: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	_animate_park(dt, t)
	_star.rotation.y += dt * 1.5
	_star.position.y = 2.8 + sin(t * 2.0) * 0.15
	for i in _arrows:
		_arrows[i].position.y = 2.0 + absf(sin(t * 5.0)) * 0.4
	var s: Dictionary = Net.party
	for pid in _pieces:
		var p: Dictionary = _pieces[pid]
		var moving := _move_piece(pid, p, dt, s)
		p.block.rotation = Vector3(t * 2.3, t * 3.1, 0.0)
		if p.block.visible and not s.is_empty() and _phase == "roll" and not s.rolls.has(pid):
			p.dice.text = str(int(t * 14.0 + pid) % (Party.DICE * (2 if s.doubled.has(pid) else 1)) + 1)  # whirling until you hit it
		var winner: bool = _phase == "final" and not s.is_empty() and Party.standings(s)[0] == pid
		p.model.pose(dt, {speed = 4.0 if moving else 0.0, dance = winner or _phase == "intro"})
	_update_camera(dt, t)
	if Net.is_host():
		_host_clock(dt)


func _move_piece(pid: int, p: Dictionary, dt: float, s: Dictionary) -> bool:
	## Hop along the path, then any ride, then the landing. Returns whether the piece is on the go.
	if _phase != "move" or p.get("landed", true):
		return false
	p.t += dt
	var k := int(p.t / Party.HOP)
	if k < p.path.size():
		var a: Vector3 = p.from if k == 0 else p.path[k - 1]
		var b: Vector3 = p.path[k]
		var f := fmod(p.t, Party.HOP) / Party.HOP
		p.root.position = a.lerp(b, f) + Vector3(0, 0.25 + sin(PI * f) * 0.9, 0)
		var dir := b - a
		p.root.rotation.y = atan2(-dir.x, -dir.z)
		p.dice.text = str(p.path.size() - k)
		if f < dt / Party.HOP * 1.5:
			Sfx.play_ui("tick", -8.0)
		return true
	if p.warp >= 0:
		if p.warp_t < 0.0:
			p.warp_t = 0.0
			p.dice.text = ""
			_land(pid, p.events)  # "All aboard!" first
		p.warp_t += dt
		if p.warp_t < RIDE:  # round the coaster track
			var xf := _track.sample_baked_with_rotation(fmod(p.warp_t / RIDE * 0.75, 1.0) * _track.get_baked_length(), true)
			p.root.position = xf.origin + Vector3(0, 0.3, 0)
			p.root.basis = xf.basis
			return true
		var f := clampf((p.warp_t - RIDE) / 1.2, 0.0, 1.0)  # then a big leap to where it drops you
		var a := _track.sample_baked(0.75 * _track.get_baked_length(), true)
		var b := Party.pos(p.warp) + Vector3(0, 0.25, 0)
		p.root.basis = Basis(Vector3.UP, atan2(-(b - a).x, -(b - a).z))
		p.root.position = a.lerp(b, f) + Vector3(0, sin(PI * f) * 9.0, 0)
		if f < 1.0:
			return true
		p.landed = true
		_place(pid, s)
		_popup(p.root.position + Vector3(0, 2.4, 0), "Wheee!", EVENT)
		return false
	p.landed = true
	p.dice.text = ""
	_place(pid, s)
	_land(pid, p.events)
	return false


func _land(pid: int, events: Array) -> void:
	var at: Vector3 = _pieces[pid].root.position + Vector3(0, 2.4, 0)
	var delay := 0.0
	for e in events:
		var text := ""
		var col := UI.LIGHT
		match e[0]:
			"star":
				text = "Star!"
				col = Color("ffcc33")
				Sfx.play_ui("strike")
			"broke":
				text = "Need %d coins for the star" % Party.STAR_COST
				col = Color("ffb0b0")
			"coins", "lucky", "booth", "strike", "struck":
				text = {coins = "", lucky = "Lucky! ", booth = "The bank pays out! ", strike = "STRIKE! ", struck = "Bowled over! "}[e[0]] \
					+ ("%+d" % e[1])
				col = Color("9cc4ff") if e[1] >= 0 else Color("ff8f8f")
				if e[1] > 0:
					_coin_burst(at - Vector3(0, 1.4, 0), mini(e[1], 12))
					Sfx.play_ui("ding", -6.0)
				if e[0] == "strike":
					Sfx.play("pins", at, 0.0)
			"item":
				text = "Got a %s!" % Party.ITEMS[e[1]].name
				col = Color("ffd166")
				Sfx.play_ui("spare", -4.0)
			"gull", "gull_item":
				_seagull(at - Vector3(0, 1.4, 0))
				text = "A seagull took %d coins!" % -e[1] if e[0] == "gull" else "A seagull took your %s!" % Party.ITEMS[e[1]].name
				col = Color("d9c8ff")
			"coaster":
				text = "All aboard!"
				col = EVENT
				Sfx.play_ui("go", -4.0)
			"wheel":
				text = "Prize wheel: " + e[1]
				col = Color("ffd166")
				Sfx.play_ui("spare", -4.0)
			"duel", "dueled":
				var foe: String = Net.players[e[1]].name if Net.players.has(e[1]) else "someone"
				text = "Sumo duel with %s: %d vs %d  %s" % [foe, e[2], e[3], "%+d" % e[4] if e[4] != 0 else "tie!"]
				col = Color("9cc4ff") if e[4] >= 0 else Color("ff8f8f")
		if text != "":
			_popup(at, text, col, delay)
			delay += 0.7


# ---------------------------------------------------------------- host clock

func _host_clock(dt: float) -> void:
	var s: Dictionary = Net.party
	_host_t += dt
	match _phase:
		"roll":
			var present: Array = s.players.keys().filter(func(pid): return Net.players.has(pid))
			for pid in Party.waiting_on(s, present):
				if Net.players[pid].bot:
					if not _bot_at.has(pid):
						_bot_at[pid] = randf_range(0.8, 2.5)
					if _host_t > _bot_at[pid]:
						for i in range(s.players[pid].items.size() - 1, -1, -1):  # bots use whatever they've got
							if randf() < 0.7:
								Net.party_use_for(pid, i)
						Net.party_roll_for(pid)
				elif _host_t > ROLL_TIMEOUT:
					Net.party_roll_for(pid)  # rolled for you
			if Party.waiting_on(s, present).is_empty() and not present.is_empty():
				Party.resolve(s)
				Net.push_party()
		"move":
			if _host_t > s.move_time:
				Party.after_move(s)
				Net.push_party()
		"choose":
			for pid in s.forks.keys():
				var human: bool = Net.players.has(pid) and not Net.players[pid].bot
				if not _bot_at.has(pid):
					_bot_at[pid] = CHOOSE_TIMEOUT if human else randf_range(0.6, 1.4)
				if _host_t > _bot_at[pid] or not Net.players.has(pid):
					var opts: Array = s.forks[pid]
					opts = opts.duplicate()
					opts.sort_custom(func(a, b): return Party.steps_to(a, s.star) < Party.steps_to(b, s.star))
					Net.party_choose_for(pid, opts[0] if randf() < 0.7 else opts.pick_random())  # bots like the way to the star
		"intro":
			if _host_t > INTRO:
				_host_t = -999.0  # once
				Net.map = s.next_game
				Net.start_match(Arena.maps()[s.next_game].seconds)
		"final":
			if _host_t > FINAL:
				_host_t = -999.0
				Net.end_party()


# ---------------------------------------------------------------- the camera

func _update_camera(dt: float, t: float) -> void:
	## The whole park while everyone rolls; close behind your own piece while it moves (and lands) or waits at a fork.
	var me: Dictionary = _pieces.get(Net.my_id(), {})
	var s: Dictionary = Net.party
	var want := OVERVIEW + Vector3(sin(t * 0.12) * 2.0, 0, 0)
	var look := OVERVIEW_LOOK
	if not me.is_empty() and not s.is_empty() and ((_phase == "choose" and s.forks.has(Net.my_id())) or (_phase == "move" and s.moves.has(Net.my_id()))):
		look = me.root.position
		want = look + Vector3(0, 12.0, 13.0)
	var k := 1.0 - exp(-dt * 2.2)
	_cam_at = _cam_at.lerp(want, k)
	_cam_look = _cam_look.lerp(look, k)
	_cam.position = _cam_at
	_cam.look_at(_cam_look)


# ---------------------------------------------------------------- the park

func _environment() -> void:
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color("4a9cf0")
	psm.sky_horizon_color = Color("c8e8ff")
	psm.ground_horizon_color = Color("c8e8ff")
	psm.ground_bottom_color = Color("2f7fc8")
	sky.sky_material = psm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("dff0ff")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = not Look.fast()
	env.glow_intensity = 0.35
	if Look.high():
		Look.dress_env(env, Color("eaf4ff"), 0.0008)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.2
	sun.light_color = Color("fff4e0")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	if Look.fast():
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 45.0
	add_child(_cam)
	_cam.current = true


func _island() -> void:
	## An island with a wobbly coastline: sand, then grass on top, in a blue sea.
	var sea := PlaneMesh.new()
	sea.size = Vector2(400, 400)
	var water := Look.toy(Color("2f86d6"), 0.08, false)
	water.metallic = 0.3
	Look.mesh(self, sea, water, Vector3(0, -0.9, 0))
	Look.mesh(self, _blob(1.06, 0.6), _matte(Color("e2c98a")), Vector3(0, -0.12, 0))
	Look.mesh(self, _blob(1.0, 0.7), _matte(Color("5fae45")), Vector3(0, -0.02, 0))
	var plaza := CylinderMesh.new()  # paving round the carousel and the fountain
	plaza.top_radius = 6.5
	plaza.bottom_radius = 6.5
	plaza.height = 0.06
	plaza.radial_segments = 48
	Look.mesh(self, plaza, _matte(Color("c9b08a")), Vector3(3.0, 0.0, -6.0)).scale = Vector3(1.35, 1, 0.8)


func _matte(c: Color) -> StandardMaterial3D:
	## Big flat ground: no toy shine or rim light, which would wash a whole lawn out.
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	m.metallic_specular = 0.2
	return m


func _blob(scale: float, depth: float) -> ArrayMesh:
	## The island's outline as a flat-topped slab: an ellipse with a few lumps.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 72
	var rim := []
	for k in n:
		var a := TAU * k / n
		var r := (1.0 + 0.05 * sin(a * 3.0) + 0.035 * sin(a * 5.0 + 1.0)) * scale
		rim.append(Vector3(cos(a) * 34.5 * r, 0.0, -3.0 + sin(a) * 26.5 * r))
	var c := Vector3(0, 0, -3)
	for k in n:
		var a: Vector3 = rim[k]
		var b: Vector3 = rim[(k + 1) % n]
		for v in [c, a, b, a, b - Vector3(0, depth, 0), b, a, a - Vector3(0, depth, 0), b - Vector3(0, depth, 0)]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _paths() -> void:
	## Paved walks between the spaces, then the spaces on top: a white rim round a coloured face with its mark.
	var paving := _matte(Color("c8a374"))
	for i in Party.SPACES.size():
		for n in Party.next_spaces(i):
			var a := Party.pos(i)
			var b := Party.pos(n)
			var walk := Look.mesh(self, Look.box(Vector3(1.3, 0.08, a.distance_to(b))), paving, (a + b) * 0.5 + Vector3(0, 0.03, 0))
			walk.rotation.y = atan2(b.x - a.x, b.z - a.z)
	var rim := CylinderMesh.new()
	rim.top_radius = 0.95
	rim.bottom_radius = 1.0
	rim.height = 0.24
	var face := CylinderMesh.new()
	face.top_radius = 0.78
	face.bottom_radius = 0.78
	face.height = 0.05
	var rim_mat := Look.toy(Color("fffaf2"), 0.3)
	var mats := {}
	for k in SPACE_COLORS:
		mats[k] = Look.toy(SPACE_COLORS[k], 0.25, false) if not k in "DCPW" else Look.neon(EVENT, 0.6)
	for i in Party.SPACES.size():
		var kind := Party.kind(i)
		var at := Party.pos(i)
		Look.mesh(self, rim, rim_mat, at + Vector3(0, 0.12, 0))
		Look.mesh(self, face, mats[kind], at + Vector3(0, 0.25, 0))
		var l := Label3D.new()
		l.text = SPACE_MARKS[kind]
		l.font = Look.title_font()
		l.font_size = 96 if SPACE_MARKS[kind].length() <= 2 else 64
		l.outline_size = 0
		l.modulate = UI.DARK if kind == "S" else Color(1, 1, 1, 0.92)
		l.pixel_size = 0.0085 if SPACE_MARKS[kind].length() <= 2 else 0.0068
		l.rotation_degrees.x = -90.0  # painted on the space
		l.position = at + Vector3(0, 0.29, 0)
		add_child(l)
	for fork in Party.FORKS:  # a signpost at each fork naming where each way goes
		var at := Party.pos(fork)
		var opts: Dictionary = Party.FORKS[fork]
		var side := (Party.pos(opts.keys()[0]) - at).cross(Vector3.UP).normalized()
		var post := Look.mesh(self, Look.box(Vector3(0.14, 2.6, 0.14)), Look.toy(Color("8a5a36"), 0.8), at + side * 2.4 + Vector3(0, 1.3, 0))
		var y := 2.3
		for to in opts:
			var dir := (Party.pos(to) - at).normalized()
			var sign := Label3D.new()
			sign.text = ("< " if dir.x < 0.0 else "") + opts[to] + (" >" if dir.x >= 0.0 else "")
			sign.font = Look.title_font()
			sign.font_size = 72
			sign.outline_size = 18
			sign.outline_modulate = Color("5a3a20")
			sign.modulate = UI.LIGHT
			sign.pixel_size = 0.01
			sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			sign.position = post.position + Vector3(0, y - 1.3, 0)
			add_child(sign)
			y -= 0.8


func _landmarks() -> void:
	_gate(Vector3(1.5, 0, 17.4))
	_booth(Vector3(7.0, 0, 16.6))
	_ferris_wheel(Vector3(-6.0, 0, -21.5))
	_coaster()
	_merry_go_round(Vector3(7.5, 0, -5.5))
	_fountain(Vector3(-1.5, 0, -7.0))
	_bowling_alley(Vector3(-26.5, 0, 0.5))
	_dojo(Vector3(26.0, 0, -0.5))
	_lake(Vector3(-14.0, 0, 13.6))
	# The prize wheel stands over its space; arcade games and snack tables fill the corners.
	Dressing.prop(self, "arcade/prize-wheel", Vector3(4.0, 0, 1.6), 0.0, 5.0)
	for k in 4:
		Dressing.prop(self, ["arcade/arcade-machine", "arcade/claw-machine", "arcade/basketball-game", "arcade/dance-machine"][k],
			Vector3(-9.0 + k * 2.2, 0, 6.8), 180.0, 2.4)
	for at in [Vector3(10.5, 0, 8.8), Vector3(-11.0, 0, -2.0), Vector3(13.5, 0, -4.0)]:
		Dressing.prop(self, "city/detail-parasol-a", at, 0.0, 3.0)
		Dressing.prop(self, "furniture/tableRound", at, 0.0, 2.2)


func _sign(parent: Node3D, text: String, at: Vector3, size: int, fill: Color, ink: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = Look.title_font()
	l.font_size = size
	l.outline_size = size / 6
	l.modulate = fill
	l.outline_modulate = ink
	l.pixel_size = 0.01
	l.position = at
	parent.add_child(l)
	return l


func _cyl(r_top: float, r_bottom: float, h: float, segs := 24) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = h
	c.radial_segments = segs
	return c


func _gate(at: Vector3) -> void:
	## The way in: two candy-striped pillars, the park's name across the top and a bunch of balloons.
	var red := Look.toy(Color("e5383b"), 0.3)
	var cream := Look.toy(Color("fff4df"), 0.3)
	for x in [-3.2, 3.2]:
		for k in 6:
			Look.mesh(self, _cyl(0.5, 0.5, 1.0), red if k % 2 == 0 else cream, at + Vector3(x, 0.5 + k, 0))
		Look.mesh(self, Look.sphere(0.6), Look.toy(Color("ffcc33"), 0.2), at + Vector3(x, 6.4, 0))
	Look.mesh(self, Look.box(Vector3(7.6, 1.3, 0.7)), Look.toy(Color("3a86ff"), 0.3), at + Vector3(0, 5.6, 0))
	_sign(self, "PARTY PARK", at + Vector3(0, 5.6, 0.4), 150, UI.LIGHT, Color("e5383b"))
	var cols := [Color("e5383b"), Color("ffcc33"), Color("3ddc97"), Color("3a86ff"), Color("ff7ab8")]
	for k in 7:
		var b := Look.mesh(self, Look.sphere(0.42, 0.52), Look.toy(cols[k % cols.size()], 0.15),
			at + Vector3(4.2 + sin(k * 2.1) * 0.7, 6.6 + k % 3 * 0.5, cos(k * 1.7) * 0.6))
		_bobbers.append(b)


func _booth(at: Vector3) -> void:
	## The ticket booth: passing it costs a few coins, landing on its space wins the lot (the bank board says how much).
	Look.mesh(self, Look.box(Vector3(2.4, 2.4, 2.0)), Look.toy(Color("158f89"), 0.4), at + Vector3(0, 1.2, 0))
	Look.mesh(self, Look.box(Vector3(1.6, 0.9, 0.1)), Look.toy(Color("bfe6ff"), 0.05), at + Vector3(0, 1.5, 1.01))
	var roof := Look.mesh(self, _cyl(0.0, 2.1, 1.2, 4), Look.toy(Color("e5383b"), 0.3), at + Vector3(0, 3.0, 0))
	roof.rotation.y = PI * 0.25
	_bank = _sign(self, "BANK\n0", at + Vector3(0, 4.4, 0), 90, Color("ffcc33"), UI.DARK)
	_bank.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y


func _ferris_wheel(at: Vector3) -> void:
	## A big wheel turning slowly behind the park, its gondolas always hanging level.
	var steel := Look.toy(Color("fff4df"), 0.3)
	var hub := at + Vector3(0, 7.5, 0)
	for side in [-1.0, 1.0]:
		for lean in [-1.0, 1.0]:
			var leg := Look.mesh(self, Look.box(Vector3(0.3, 8.6, 0.3)), steel, at + Vector3(lean * 2.2, 3.75, side * 0.9))
			leg.rotation.z = lean * 0.29
	_wheel = Node3D.new()
	_wheel.position = hub
	add_child(_wheel)
	var rim := TorusMesh.new()
	rim.inner_radius = 5.85
	rim.outer_radius = 6.15
	rim.rings = 64
	Look.mesh(_wheel, rim, Look.toy(Color("e5383b"), 0.3)).rotation.x = PI * 0.5
	for k in 8:
		var spoke := Look.mesh(_wheel, Look.box(Vector3(0.12, 12.0, 0.12)), steel)
		spoke.rotation.z = PI * k / 8.0
	Look.mesh(_wheel, Look.sphere(0.6), Look.toy(Color("ffcc33"), 0.2))
	var cols := [Color("3a86ff"), Color("ffcc33"), Color("3ddc97"), Color("ff7ab8")]
	for k in 8:
		var g := Node3D.new()
		add_child(g)
		Look.mesh(g, Look.box(Vector3(1.0, 0.9, 0.9)), Look.toy(cols[k % 4], 0.3), Vector3(0, -0.6, 0))
		Look.mesh(g, _cyl(0.1, 0.65, 0.35, 4), Look.toy(Color("fff4df"), 0.3), Vector3(0, -0.02, 0)).rotation.y = PI * 0.25
		_gondolas.append(g)


func _coaster() -> void:
	## The roller coaster: one smooth loop of track (a Curve3D, so the ride can follow it) on posts, a car racing round.
	for k in COASTER.size():
		var prev: Vector3 = COASTER[(k - 1 + COASTER.size()) % COASTER.size()]
		var next: Vector3 = COASTER[(k + 1) % COASTER.size()]
		var h := (next - prev) / 6.0  # Catmull-Rom as Bezier handles
		_track.add_point(COASTER[k], -h, h)
	_track.add_point(COASTER[0], -(COASTER[1] - COASTER[-1]) / 6.0, (COASTER[1] - COASTER[-1]) / 6.0)
	_track.bake_interval = 0.5
	var rails := SurfaceTool.new()
	rails.begin(Mesh.PRIMITIVE_TRIANGLES)
	var posts := SurfaceTool.new()
	posts.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tie := Look.box(Vector3(1.3, 0.12, 0.25))
	var rail := Look.box(Vector3(0.14, 0.14, 0.75))
	var len := _track.get_baked_length()
	var n := int(len / 0.7)
	for k in n:
		var xf := _track.sample_baked_with_rotation(len * k / n, true)
		for side in [-0.5, 0.5]:
			rails.append_from(rail, 0, xf * Transform3D(Basis(), Vector3(side, 0, 0)))
		if k % 2 == 0:
			rails.append_from(tie, 0, xf)
		if k % 6 == 0 and xf.origin.y > 0.6:
			var post := _cyl(0.12, 0.16, xf.origin.y, 8)
			posts.append_from(post, 0, Transform3D(Basis(), Vector3(xf.origin.x, xf.origin.y * 0.5, xf.origin.z)))
	Look.mesh(self, rails.commit(), Look.toy(Color("e5383b"), 0.3, false))
	Look.mesh(self, posts.commit(), Look.toy(Color("fff4df"), 0.4, false))
	_car = Node3D.new()
	add_child(_car)
	Look.mesh(_car, Look.box(Vector3(1.2, 0.6, 2.0)), Look.toy(Color("ffcc33"), 0.2), Vector3(0, 0.35, 0))
	Look.mesh(_car, Look.box(Vector3(1.0, 0.5, 0.2)), Look.toy(Color("e5383b"), 0.2), Vector3(0, 0.8, -0.6))
	var station: Vector3 = COASTER[0]
	Look.mesh(self, Look.box(Vector3(5.0, 1.2, 2.6)), Look.toy(Color("efe3c8"), 0.8), Vector3(station.x + 2.0, 0.6, station.z))
	var roof := Look.mesh(self, _cyl(0.0, 3.6, 1.0, 4), Look.toy(Color("3a86ff"), 0.3), Vector3(station.x + 2.0, 3.6, station.z))
	roof.rotation.y = PI * 0.25
	roof.scale = Vector3(1.0, 1.0, 0.6)
	_sign(self, "COASTER", Vector3(station.x + 2.0, 4.6, station.z + 0.6), 110, UI.LIGHT, Color("3a86ff"))


func _merry_go_round(at: Vector3) -> void:
	## A carousel under a striped tent, its horses bobbing as it turns.
	Look.mesh(self, _cyl(3.3, 3.4, 0.4, 32), Look.toy(Color("fff4df"), 0.4), at + Vector3(0, 0.2, 0))
	_carousel = Node3D.new()
	_carousel.position = at
	add_child(_carousel)
	Look.mesh(_carousel, _cyl(0.25, 0.25, 4.2, 12), Look.toy(Color("ffcc33"), 0.2), Vector3(0, 2.3, 0))
	for k in 8:
		var wedge := Look.mesh(_carousel, _cyl(0.0, 3.8, 1.6, 3), Look.toy(Color("e5383b") if k % 2 == 0 else Color("fff4df"), 0.3),
			Vector3(0, 4.9, 0))
		wedge.rotation.y = TAU * k / 8.0
		wedge.scale = Vector3(0.55, 1.0, 1.0)
	var cols := [Color("fff4df"), Color("3a86ff"), Color("ff7ab8"), Color("3ddc97")]
	for k in 6:
		var a := TAU * k / 6.0
		var horse := Node3D.new()
		horse.position = Vector3(cos(a) * 2.4, 1.2, sin(a) * 2.4)
		horse.rotation.y = -a
		_carousel.add_child(horse)
		var coat := Look.toy(cols[k % 4], 0.3)
		Look.mesh(horse, Look.box(Vector3(0.35, 0.45, 1.0)), coat)
		Look.mesh(horse, Look.box(Vector3(0.28, 0.55, 0.3)), coat, Vector3(0, 0.35, -0.5)).rotation.x = 0.4
		Look.mesh(horse, _cyl(0.05, 0.05, 3.6, 6), Look.toy(Color("ffcc33"), 0.2), Vector3(0, 0.7, 0))
		_horses.append(horse)


func _fountain(at: Vector3) -> void:
	var stone := Look.toy(Color("d9cbb0"), 0.7)
	Look.mesh(self, _cyl(1.9, 2.0, 0.6, 32), stone, at + Vector3(0, 0.3, 0))
	Look.mesh(self, _cyl(1.7, 1.7, 0.05, 32), Look.toy(Color("5ab8f0"), 0.05, false), at + Vector3(0, 0.58, 0))
	Look.mesh(self, _cyl(0.25, 0.3, 1.6, 12), stone, at + Vector3(0, 1.2, 0))
	Look.mesh(self, _cyl(0.8, 0.3, 0.3, 24), stone, at + Vector3(0, 2.0, 0))
	if Look.fast():
		return
	var spray := CPUParticles3D.new()
	spray.mesh = Look.sphere(0.06)
	spray.material_override = Look.toy(Color("bfe6ff"), 0.05, false)
	spray.amount = 40
	spray.lifetime = 0.9
	spray.direction = Vector3.UP
	spray.spread = 20.0
	spray.initial_velocity_min = 3.0
	spray.initial_velocity_max = 4.0
	spray.position = at + Vector3(0, 2.2, 0)
	add_child(spray)


func _bowling_alley(at: Vector3) -> void:
	## Where the bowling minigames happen: a long hall with a giant pin and ball on the roof.
	Look.mesh(self, Look.box(Vector3(7.0, 4.0, 11.0)), Look.toy(Color("fff4df"), 0.6), at + Vector3(0, 2.0, 0))
	Look.mesh(self, Look.box(Vector3(7.4, 0.6, 11.4)), Look.toy(Color("6b4fa0"), 0.4), at + Vector3(0, 4.2, 0))
	Look.mesh(self, Look.box(Vector3(0.1, 2.4, 2.4)), Look.toy(Color("1d2340"), 0.2), at + Vector3(3.52, 1.2, 0))
	var sign := _sign(self, "BOWLING", at + Vector3(3.6, 3.1, 0), 120, Color("ffcc33"), Color("6b4fa0"))
	sign.rotation.y = PI * 0.5
	Look.mesh(self, Arena.pin_mesh(), Arena.pin_material(), at + Vector3(0, 4.5, -2.2)).scale = Vector3.ONE * 3.2
	Look.mesh(self, Look.sphere(1.1), Look.toy(Color("e5383b"), 0.08), at + Vector3(0, 5.6, 2.0))


func _dojo(at: Vector3) -> void:
	## Where Sumo happens: a raised clay ring under a hanging roof with coloured tassels.
	Look.mesh(self, Look.box(Vector3(7.0, 1.0, 7.0)), Look.toy(Color("b5793f"), 0.9), at + Vector3(0, 0.5, 0))
	var rope := TorusMesh.new()
	rope.inner_radius = 2.6
	rope.outer_radius = 2.85
	Look.mesh(self, rope, Look.toy(Color("e6cf8a"), 0.85), at + Vector3(0, 1.02, 0)).scale = Vector3(1, 0.4, 1)
	var tassels := [Color("2a8f5a"), Color("e5383b"), Color("f2f2f2"), Color("1f2a44")]
	for k in 4:
		var c := Vector3(cos(PI * 0.25 + PI * 0.5 * k), 0, sin(PI * 0.25 + PI * 0.5 * k)) * 4.2
		Look.mesh(self, _cyl(0.15, 0.18, 5.6, 8), Look.toy(Color("8a5a36"), 0.6), at + c + Vector3(0, 2.8, 0))
		Look.mesh(self, Look.sphere(0.4), Look.toy(tassels[k], 0.6), at + c + Vector3(0, 5.0, 0))
	var roof := Look.mesh(self, _cyl(0.4, 5.4, 1.8, 4), Look.toy(Color("5a3a20"), 0.6), at + Vector3(0, 6.5, 0))
	roof.rotation.y = PI * 0.25
	_sign(self, "SUMO", at + Vector3(0, 8.2, 0), 140, UI.LIGHT, Color("b33a2e")).billboard = BaseMaterial3D.BILLBOARD_FIXED_Y


func _lake(at: Vector3) -> void:
	var pond := Look.mesh(self, _cyl(2.4, 2.4, 0.08, 40), Look.toy(Color("3d9be0"), 0.05, false), at + Vector3(0, 0.02, 0))
	pond.scale = Vector3(1.35, 1, 0.9)
	for k in 4:
		Look.mesh(self, _cyl(0.35, 0.35, 0.03, 12), Look.toy(Color("4caf50"), 0.6, false),
			at + Vector3(cos(k * 1.9) * 2.0, 0.07, sin(k * 1.9) * 1.2))
	_duck = Node3D.new()
	_duck.set_meta("home", at)
	add_child(_duck)
	Look.mesh(_duck, Look.sphere(0.32, 0.4), Look.toy(Color("ffd84d"), 0.3), Vector3(0, 0.15, 0))
	Look.mesh(_duck, Look.sphere(0.18), Look.toy(Color("ffd84d"), 0.3), Vector3(0, 0.45, -0.22))
	Look.mesh(_duck, Look.box(Vector3(0.12, 0.06, 0.16)), Look.toy(Color("ff8c2a"), 0.3), Vector3(0, 0.42, -0.42))


func _greenery() -> void:
	## Palms along the shore and bushes and flowers on any lawn not taken by a path or a ride.
	_rng.seed = 7
	var taken := [Vector3(-6, 0, -21.5), Vector3(17, 0, -21), Vector3(7.5, 0, -5.5), Vector3(-1.5, 0, -7), Vector3(-26.5, 0, 0.5),
		Vector3(26, 0, -0.5), Vector3(-14, 0, 13.6), Vector3(1.5, 0, 17.4), Vector3(4, 0, 1.6)] + COASTER.map(func(c): return c * Vector3(1, 0, 1))
	var palms := 12 if Look.fast() else 28
	for k in palms:
		var a := TAU * (k + _rng.randf() * 0.5) / palms
		var at := Vector3(cos(a) * 31.0, 0, -3.0 + sin(a) * 23.0)
		if _clear(at, taken, 4.5):
			Dressing.prop(self, ["nature/tree_palmDetailedTall", "nature/tree_palmBend", "nature/tree_palmTall"][k % 3], at, _rng.randf_range(0, 360), 3.4)
	for k in (14 if Look.fast() else 40):
		var at := Vector3(_rng.randf_range(-28, 28), 0, _rng.randf_range(-24, 18))
		if _clear(at, taken, 5.0) and absf(at.x) < 30.0 * sqrt(maxf(1.0 - pow((at.z + 3.0) / 23.0, 2.0), 0.0)):
			var flower := k % 3 != 0
			Dressing.prop(self, ["nature/flower_redA", "nature/flower_yellowA", "nature/flower_purpleA"][k % 3] if flower else "nature/plant_bushLarge",
				at, _rng.randf_range(0, 360), 4.0 if flower else 2.6)


func _clear(at: Vector3, taken: Array, room: float) -> bool:
	for i in Party.SPACES.size():
		if Party.pos(i).distance_to(at) < 2.2:
			return false
	return taken.all(func(t): return t.distance_to(at) > room)


func _star_and_arrows() -> void:
	## The star: a fat gold five-pointer spinning over its space, on a glowing ring. And the arrows a fork shows you.
	_star = Node3D.new()
	add_child(_star)
	Look.mesh(_star, _star_mesh(1.8, 0.8, 0.4), Look.neon(Color("ffcc33"), 0.8))
	var halo := TorusMesh.new()
	halo.inner_radius = 1.05
	halo.outer_radius = 1.25
	_halo = Look.mesh(self, halo, Look.neon(Color("ffcc33"), 1.5))
	_halo.scale = Vector3(1, 0.3, 1)
	var arrow := _cyl(0.0, 0.45, 0.8, 12)
	for fork in Party.FORKS:
		for to in Party.FORKS[fork]:
			var a := Look.mesh(self, arrow, Look.neon(Color("ffcc33"), 1.2), Party.pos(to) + Vector3(0, 2.0, 0))
			a.rotation.x = PI  # pointing down at the space
			a.visible = false
			_arrows[to] = a


func _animate_park(dt: float, t: float) -> void:
	_wheel.rotation.z += dt * 0.15
	for k in _gondolas.size():
		var a := _wheel.rotation.z + TAU * k / _gondolas.size()
		_gondolas[k].position = _wheel.position + Vector3(cos(a), sin(a), 0) * 6.0
	_carousel.rotation.y += dt * 0.6
	for k in _horses.size():
		_horses[k].position.y = 1.2 + sin(t * 2.5 + k * 1.3) * 0.3
	var len := _track.get_baked_length()
	_car.transform = _track.sample_baked_with_rotation(fmod(t * 9.0, len), true)
	for k in _bobbers.size():
		_bobbers[k].position.y += cos(t * 1.5 + k) * 0.3 * dt
	var home: Vector3 = _duck.get_meta("home")
	_duck.position = home + Vector3(cos(t * 0.3) * 1.6, 0.15 + sin(t * 3.0) * 0.03, sin(t * 0.3) * 0.9)
	_duck.rotation.y = -t * 0.3


func _star_mesh(r_out: float, r_in: float, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := []
	for k in 10:
		var a := TAU * k / 10.0 - PI * 0.5
		var r := r_out if k % 2 == 0 else r_in
		ring.append(Vector2(cos(a) * r, sin(a) * r))
	for side in [-1.0, 1.0]:
		var c := Vector3(0, 0, side * depth)
		for k in 10:
			var a: Vector2 = ring[k]
			var b: Vector2 = ring[(k + 1) % 10]
			var tri := [c, Vector3(a.x, -a.y, 0), Vector3(b.x, -b.y, 0)]
			if side < 0.0:
				tri.reverse()
			for v in tri:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


func _add_piece(pid: int) -> void:
	var info: Dictionary = Net.players[pid]
	var root := Node3D.new()
	add_child(root)
	var model := BowlerModel.new()
	root.add_child(model)
	model.build(info.color, info.skin)
	model.scale = Vector3.ONE * 0.75
	model.position.y = 0.55
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.52
	Look.mesh(root, ring, Look.neon(info.color.lightened(0.2), 1.5), Vector3(0, 0.02, 0)).scale = Vector3(1, 0.3, 1)
	var block := Look.mesh(root, Look.box(Vector3(0.7, 0.7, 0.7)), Look.toy(Color("ffcc33"), 0.2), Vector3(0, 2.5, 0))  # the dice block
	var dice := Label3D.new()
	dice.font = Look.title_font()
	dice.font_size = 110
	dice.outline_size = 26
	dice.outline_modulate = UI.DARK
	dice.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dice.no_depth_test = true
	dice.pixel_size = 0.0065
	dice.position.y = 2.5
	root.add_child(dice)
	_pieces[pid] = {root = root, model = model, dice = dice, block = block, path = []}
	if not Net.party.is_empty():
		_place(pid, Net.party)


func _popup(pos: Vector3, text: String, col: Color, delay := 0.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = Look.title_font()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 80
	l.outline_size = 20
	l.pixel_size = 0.007
	l.modulate = Color(col, 0.0)
	l.outline_modulate = Color(UI.DARK, 0.0)
	add_child(l)
	l.position = pos
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "modulate:a", 1.0, 0.1).set_delay(delay)
	tw.tween_property(l, "outline_modulate:a", 1.0, 0.1).set_delay(delay)
	tw.tween_property(l, "position", pos + Vector3.UP * 1.4, 1.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(delay)
	tw.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(delay + 1.5)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.4).set_delay(delay + 1.5)
	tw.chain().tween_callback(l.queue_free)


func _coin_burst(at: Vector3, n: int) -> void:
	var p := CPUParticles3D.new()
	var coin := _cyl(0.18, 0.18, 0.05, 12)
	p.mesh = coin
	p.material_override = Look.neon(Color("ffcc33"), 0.6)
	p.one_shot = true
	p.explosiveness = 0.8
	p.amount = maxi(n, 2)
	p.lifetime = 0.9
	p.direction = Vector3.UP
	p.spread = 30.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 6.0
	p.angular_velocity_min = 360.0
	p.angular_velocity_max = 720.0
	p.position = at + Vector3(0, 1.0, 0)
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


func _seagull(at: Vector3) -> void:
	## A gull swoops in over the space and off with the loot.
	var gull := Node3D.new()
	add_child(gull)
	var white := Look.toy(Color("fbfbfb"), 0.4)
	Look.mesh(gull, Look.sphere(0.3, 0.4), white).scale = Vector3(0.8, 0.8, 1.6)
	for side in [-1.0, 1.0]:
		var wing := Look.mesh(gull, Look.box(Vector3(1.1, 0.06, 0.4)), white, Vector3(side * 0.6, 0.1, 0))
		wing.rotation.z = side * 0.35
	Look.mesh(gull, Look.box(Vector3(0.08, 0.08, 0.25)), Look.toy(Color("ffb400"), 0.3), Vector3(0, 0, -0.55))
	var from := at + Vector3(-14, 8, 6)
	gull.position = from
	gull.look_at_from_position(from, at + Vector3(0, 1.2, 0))
	var tw := gull.create_tween()
	tw.tween_property(gull, "position", at + Vector3(0, 1.4, 0), 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(gull, "position", at + Vector3(14, 10, -8), 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(gull.queue_free)


# ---------------------------------------------------------------- the board's screen

class Icon extends Control:
	## A tiny star or coin, drawn, so it never depends on a font having the glyph.
	var star := true
	func _init(is_star: bool) -> void:
		star = is_star
		custom_minimum_size = Vector2(24, 24)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func _draw() -> void:
		var c := size * 0.5
		if star:
			var pts := PackedVector2Array()
			for k in 10:
				var a := TAU * k / 10.0 - PI * 0.5
				pts.append(c + Vector2(cos(a), sin(a)) * (11.0 if k % 2 == 0 else 4.8))
			draw_colored_polygon(pts, Color("ffb400"))
		else:
			draw_circle(c, 10.0, Color("e09a00"))
			draw_circle(c, 7.0, Color("ffcc33"))


func _hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = UI.theme()
	layer.add_child(_ui)
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.offset_top = 14
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ui.add_child(top)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -2)
	top.add_child(tv)
	_round = UI.label(tv, "", 40, UI.NAVY, true)
	_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub = UI.label(tv, "", 19, Color(UI.NAVY, 0.7))
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_news = UI.hero(_ui, "", 30)
	_news.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_news.offset_top = 130
	_news.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_news.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cards = VBoxContainer.new()
	_cards.position = Vector2(18, 18)
	_cards.add_theme_constant_override("separation", 6)
	_ui.add_child(_cards)
	_roll = UI.primary(UI.button(_ui, "Roll!", func(): Net.party_roll(), 300))
	_roll.add_theme_font_size_override("font_size", 48)
	_roll.custom_minimum_size.y = 88
	_roll.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)  # clear of the park's gate
	_roll.offset_left = -340
	_roll.offset_right = -40
	_roll.offset_top = -130
	_roll.offset_bottom = -42
	_items = HBoxContainer.new()  # the item buttons, over Roll
	_items.add_theme_constant_override("separation", 12)
	_items.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_items.offset_top = -220
	_items.offset_bottom = -150
	_items.offset_right = -40
	_items.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ui.add_child(_items)
	_fork = HBoxContainer.new()  # the ways to go at a fork
	_fork.add_theme_constant_override("separation", 16)
	_fork.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_fork.offset_top = -140
	_fork.offset_bottom = -60
	_fork.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ui.add_child(_fork)
	_intro = _center_card()
	var iv: VBoxContainer = _intro.get_node("V")
	UI.label(iv, "Next minigame", 24, UI.RED, true)
	var game_name := UI.label(iv, "", 72, UI.NAVY, true)
	game_name.name = "Name"
	var rules := UI.label(iv, "", 24, Color(UI.NAVY, 0.75))
	rules.name = "Rules"
	rules.custom_minimum_size.x = 620
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_final = _center_card()


func _center_card() -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.visible = false
	_ui.add_child(p)
	var v := VBoxContainer.new()
	v.name = "V"
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	return p


func _refresh_hud(s: Dictionary) -> void:
	var me := Net.my_id()
	_round.text = ("Round %d of %d" % [mini(s.round, s.rounds), s.rounds] + ("  ·  Last round!" if s.round == s.rounds else "")) \
		if s.phase != "final" else "Party over!"
	var present: Array = s.players.keys().filter(func(pid): return Net.players.has(pid))
	match s.phase:
		"roll":
			var waiting := Party.waiting_on(s, present).size()
			var last := ""
			if not s.result.is_empty() and Net.players.has(s.result[0][0]):
				last = "%s won %s  ·  " % [Net.players[s.result[0][0]].name, Arena.maps()[s.last_game].name]
			_sub.text = last + ("Everyone roll!" if waiting == present.size() else "Waiting on %d..." % waiting)
		"move":
			_sub.text = "Hop hop hop..."
		"choose":
			_sub.text = "Pick a way!" if s.forks.has(me) else "Waiting at a fork..."
		"intro":
			_sub.text = "Get ready!"
		_:
			_sub.text = ""
	var can_roll: bool = s.phase == "roll" and s.players.has(me) and not s.rolls.has(me)
	_roll.visible = can_roll
	_roll.text = "Roll two dice!" if s.doubled.has(me) else "Roll!"
	for c in _items.get_children():
		c.queue_free()
	if can_roll:
		var bag: Array = s.players[me].items
		for i in bag.size():
			if bag[i] == "double" and s.doubled.has(me):
				continue
			var item: Dictionary = Party.ITEMS[bag[i]]
			var b := UI.button(_items, "Use %s" % item.name, func(): Net.party_use(i), 280)
			b.tooltip_text = UI.sentence(item.hint)
	for c in _fork.get_children():
		c.queue_free()
	for i in _arrows:
		_arrows[i].visible = false
	if s.phase == "choose" and s.forks.has(me):
		var fork: int = s.players[me].space
		for to in s.forks[me]:
			UI.primary(UI.button(_fork, Party.FORKS[fork][to], func(): Net.party_choose(to), 300))
			_arrows[to].visible = true
	for c in _cards.get_children():
		c.queue_free()
	var rank := 0
	for pid in Party.standings(s):
		if not Net.players.has(pid):
			continue
		rank += 1
		var p: Dictionary = s.players[pid]
		var card := PanelContainer.new()
		var style := UI.card(UI.PAPER if pid != me else UI.CREAM, 16, 3)
		style.border_color = Net.players[pid].color
		style.border_width_left = 10
		style.content_margin_top = 6
		style.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", style)
		card.custom_minimum_size.x = 300
		_cards.add_child(card)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", -4)
		card.add_child(col)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		col.add_child(row)
		UI.label(row, str(rank), 22, Color(UI.NAVY, 0.5), true)
		var name := UI.label(row, Net.players[pid].name, 22, UI.ink(Net.players[pid].color), true)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(Icon.new(true))
		UI.label(row, str(p.stars), 22, UI.NAVY, true)
		row.add_child(Icon.new(false))
		UI.label(row, str(p.coins), 22, UI.NAVY, true)
		if not p.items.is_empty():
			UI.label(col, "    " + "  ·  ".join(p.items.map(func(k): return Party.ITEMS[k].name)), 15, Color(UI.NAVY, 0.6))


func _unhandled_input(e: InputEvent) -> void:
	if _roll.visible and (e.is_action_pressed("punch") or e.is_action_pressed("jump") or e.is_action_pressed("ui_accept")):
		Net.party_roll()
	var s: Dictionary = Net.party
	if not s.is_empty() and s.phase == "choose" and s.forks.has(Net.my_id()) and (e.is_action_pressed("left") or e.is_action_pressed("right")):
		var opts: Array = s.forks[Net.my_id()].duplicate()
		opts.sort_custom(func(a, b): return Party.pos(a).x < Party.pos(b).x)  # the camera looks north: west is left
		Net.party_choose(opts[0] if e.is_action_pressed("left") else opts[-1])


func _show_final(s: Dictionary) -> void:
	var v: VBoxContainer = _final.get_node("V")
	for c in v.get_children():
		c.queue_free()
	var order := Party.standings(s).filter(func(pid): return Net.players.has(pid))
	if order.is_empty():
		return
	for b in s.bonus:  # Mario Party's bonus stars, already counted in the standings
		var names: Array = b[1].filter(func(pid): return Net.players.has(pid)).map(func(pid): return Net.players[pid].name)
		if not names.is_empty():
			UI.label(v, "%s:  %s" % [b[0], ", ".join(names)], 22, UI.TEAL, true)
	UI.label(v, "Party winner!", 30, UI.RED, true)
	UI.label(v, Net.players[order[0]].name, 80, UI.NAVY, true)
	var table := GridContainer.new()
	table.columns = 4
	table.add_theme_constant_override("h_separation", 26)
	v.add_child(table)
	for i in order.size():
		var p: Dictionary = s.players[order[i]]
		UI.label(table, str(i + 1), 26, UI.NAVY, true)
		UI.label(table, Net.players[order[i]].name, 26, UI.ink(Net.players[order[i]].color), true)
		UI.label(table, "%d star%s" % [p.stars, "" if p.stars == 1 else "s"], 24, UI.NAVY, true)
		UI.label(table, "%d coins" % p.coins, 24, Color(UI.NAVY, 0.7))
	if not _banked and not Net.party_mine.is_empty():  # the whole party counts as one match for XP and trophies
		_banked = true
		var row: Dictionary = Net.party_mine.duplicate()
		var prog := Progress.finish_match(row, order[0] == Net.my_id(), row.get("feats", {}))
		Progress.fresh = prog.unlocks
		UI.label(v, "+%d XP" % prog.xp, 26, UI.RED, true)
	if Net.is_host():
		UI.primary(UI.button(v, "Back to the lobby", Net.end_party, 340))
	else:
		UI.label(v, "Back to the lobby soon...", 18, Color(UI.NAVY, 0.6))
	UI.pop_in.call_deferred(_final)
	Music.play("victory", 0.2)
