class_name Board
extends Node3D
## The party board, drawn from Net.party on every peer: an island with a loop of spaces, everyone's bowler as a piece.
## The host also keeps time: bots' rolls, a roll timeout, the beat after moving, and the minigame intro.

const HOP := 0.3  # seconds per space (Party.resolve budgets the same)
const ROLL_TIMEOUT := 15.0
const INTRO := 4.0
const FINAL := 25.0  # then the host takes everyone back to the lobby
const SPACE_COLORS := {S = Color("fff4df"), B = Color("3a86ff"), R = Color("e5383b"), L = Color("3ddc97")}

var _spaces: Array[Vector3] = []
var _pieces := {}  # pid -> {root, model, dice, path: Array[Vector3], t, events}
var _star: Node3D
var _cam: Camera3D
var _ui: Control
var _round: Label
var _sub: Label
var _cards: VBoxContainer
var _roll: Button
var _intro: PanelContainer
var _final: PanelContainer
var _phase := ""
var _host_t := 0.0
var _bot_at := {}
var _banked := false


func _ready() -> void:
	UI.use(false)  # a sunny island: the light palette
	_environment()
	_island()
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
	_star.position = _spaces[s.star] + Vector3(0, 2.2, 0)
	var halo: Node3D = get_node("StarHalo")
	halo.position = _spaces[s.star] + Vector3(0, 0.26, 0)
	halo.scale = Vector3(1, 0.3, 1)
	if s.phase != _phase:
		_enter(s.phase, s)
	for pid in _pieces:  # dice show what each player rolled
		var dice: Label3D = _pieces[pid].dice
		if s.phase == "roll":
			dice.text = str(s.rolls[pid]) if s.rolls.has(pid) else "?"
			dice.modulate = UI.LIGHT if s.rolls.has(pid) else Color(1, 1, 1, 0.5)
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
			Sfx.play_ui("beep")
		"move":
			for pid in s.moves:
				if _pieces.has(pid):
					var m: Dictionary = s.moves[pid]
					var p: Dictionary = _pieces[pid]
					p.path = []
					for k in m.steps:
						p.path.append(_spaces[(m.from + k + 1) % Party.SPACES])
					p.t = 0.0
					p.landed = false
					p.from = _spaces[m.from]
					p.events = m.events
					p.dice.text = str(m.steps)
		"intro":
			var g: Dictionary = Party.MINIGAMES[s.next_game]
			_intro.get_node("V/Name").text = g.name
			_intro.get_node("V/Rules").text = g.rules
			UI.pop_in.call_deferred(_intro)
			Sfx.play_ui("go")
			for pid in _pieces:
				_pieces[pid].dice.visible = false
		"final":
			_show_final(s)


func _place(pid: int, s: Dictionary) -> void:
	## Pieces sharing a space stand in a little circle.
	var space: int = s.players[pid].space
	var here: Array = s.players.keys().filter(func(o): return s.players[o].space == space and _pieces.has(o))
	var i: int = here.find(pid)
	var r := 0.35 + 0.12 * here.size()  # a crowd on one space stands in a wider circle
	var off := Vector3.ZERO if here.size() == 1 else Vector3(cos(TAU * i / here.size()), 0, sin(TAU * i / here.size())) * r
	_pieces[pid].root.position = _spaces[space] + off + Vector3(0, 0.25, 0)


func _process(dt: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	_star.rotation.y += dt * 1.5
	_star.position.y = 2.2 + sin(t * 2.0) * 0.15
	_cam.position = Vector3(sin(t * 0.12) * 2.0, 25.0, 17.0)
	_cam.look_at(Vector3(0, 0, 0.8))
	var s: Dictionary = Net.party
	for pid in _pieces:
		var p: Dictionary = _pieces[pid]
		var moving := false
		if _phase == "move" and not p.get("path", []).is_empty():
			p.t += dt
			var k := mini(int(p.t / HOP), p.path.size())
			if k < p.path.size():
				moving = true
				var a: Vector3 = p.from if k == 0 else p.path[k - 1]
				var b: Vector3 = p.path[k]
				var f := fmod(p.t, HOP) / HOP
				p.root.position = a.lerp(b, f) + Vector3(0, 0.25 + sin(PI * f) * 0.9, 0)
				var dir := b - a
				p.root.rotation.y = atan2(-dir.x, -dir.z)
				p.dice.text = str(p.path.size() - k)
			elif not p.get("landed", true):
				p.landed = true
				p.dice.text = ""
				_place(pid, s)
				_land(pid, p.events)
		var winner: bool = _phase == "final" and not s.is_empty() and Party.standings(s)[0] == pid
		p.model.pose(dt, {speed = 4.0 if moving else 0.0, dance = winner or _phase == "intro"})
	if Net.is_host():
		_host_clock(dt)


func _land(pid: int, events: Array) -> void:
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
			"blue":
				text = "+%d" % e[1]
				col = Color("9cc4ff")
			"red":
				text = "%d" % e[1]
				col = Color("ff8f8f")
			"lucky":
				text = "Lucky! +%d" % e[1]
				col = Color("8ff0c0")
		_popup(_pieces[pid].root.position + Vector3(0, 2.4, 0), text, col)


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
						Net.party_roll_for(pid)
				elif _host_t > ROLL_TIMEOUT:
					Net.party_roll_for(pid)  # rolled for you
			if Party.waiting_on(s, present).is_empty() and not present.is_empty():
				Party.resolve(s)
				Net.push_party()
		"move":
			if _host_t > s.move_time:
				Party.pick_minigame(s)
				Net.push_party()
		"intro":
			if _host_t > INTRO:
				_host_t = -999.0  # once
				Net.map = s.next_game
				Net.start_match(Party.MINIGAMES[s.next_game].seconds)
		"final":
			if _host_t > FINAL:
				_host_t = -999.0
				Net.end_party()


# ---------------------------------------------------------------- the island

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
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.2
	sun.light_color = Color("fff4e0")
	sun.shadow_enabled = true
	if Look.fast():
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 50.0
	add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 45.0
	add_child(_cam)
	_cam.current = true


func _island() -> void:
	var sea := PlaneMesh.new()
	sea.size = Vector2(300, 300)
	var water := Look.toy(Color("2f86d6"), 0.08, false)
	water.metallic = 0.3
	Look.mesh(self, sea, water, Vector3(0, -0.9, 0))
	for layer in [[23.0, Color("efd9a0"), -0.7], [21.0, Color("78c25a"), -0.5]]:  # beach, then grass
		var c := CylinderMesh.new()
		c.top_radius = layer[0]
		c.bottom_radius = layer[0] + 0.6
		c.height = 1.0
		c.radial_segments = 64
		Look.mesh(self, c, Look.toy(layer[1], 0.95, false), Vector3(0, layer[2], 0)).scale = Vector3(1, 1, 0.68)
	# The loop of spaces, with little stepping stones between them.
	for i in Party.SPACES:
		var t := TAU * i / Party.SPACES + PI * 0.5  # space 0 at the front, nearest the camera
		var c := cos(t)
		var sn := sin(t)
		_spaces.append(Vector3(14.0 * signf(c) * pow(absf(c), 0.55), 0.0, 8.5 * signf(sn) * pow(absf(sn), 0.55)))
	var disc := CylinderMesh.new()
	disc.top_radius = 0.95
	disc.bottom_radius = 1.0
	disc.height = 0.22
	var stone := Look.sphere(0.12)
	var stone_mat := Look.toy(Color("fff4df"), 0.8, false)
	for i in Party.SPACES:
		var kind: String = Party.LAYOUT[i]
		Look.mesh(self, disc, Look.toy(SPACE_COLORS[kind], 0.4), _spaces[i] + Vector3(0, 0.11, 0))
		var mark := ""
		match kind:
			"S": mark = "GO"
			"B": mark = "+3"
			"R": mark = "-3"
			"L": mark = "?"
		var l := Label3D.new()
		l.text = mark
		l.font = Look.title_font()
		l.font_size = 96
		l.outline_size = 0
		l.modulate = UI.DARK if kind == "S" else Color(1, 1, 1, 0.9)
		l.pixel_size = 0.006
		l.rotation_degrees.x = -90.0  # painted on the space
		l.position = _spaces[i] + Vector3(0, 0.23, 0)
		add_child(l)
		var nxt: Vector3 = _spaces[(i + 1) % Party.SPACES]
		for k in [0.38, 0.62]:
			Look.mesh(self, stone, stone_mat, _spaces[i].lerp(nxt, k) + Vector3(0, 0.03, 0))
	# The star: a fat gold five-pointer spinning over its space, on a glowing ring.
	_star = Node3D.new()
	add_child(_star)
	var gold := Look.neon(Color("ffcc33"), 0.8)
	Look.mesh(_star, _star_mesh(1.3, 0.58, 0.32), gold)
	var halo := TorusMesh.new()
	halo.inner_radius = 1.0
	halo.outer_radius = 1.18
	Look.mesh(self, halo, Look.neon(Color("ffcc33"), 1.5)).name = "StarHalo"
	# The middle of the island: a giant pin and ball, the party sign, and some greenery.
	Look.mesh(self, Arena.pin_mesh(), Arena.pin_material(), Vector3(-3.0, 0.0, -1.0)).scale = Vector3.ONE * 4.5
	var ball := Look.mesh(self, Look.sphere(1.3), Look.toy(Color("e5383b"), 0.08), Vector3(0.6, 1.3, -0.4))
	for o in [Vector3(-0.3, 1.1, -0.5), Vector3(0.3, 1.1, -0.5), Vector3(0.0, 1.1, 0.4)]:
		Look.mesh(ball, Look.sphere(0.2), Look.toy(Color("1d2340"), 0.6, false), o * 0.9)
	var sign := Label3D.new()
	sign.text = "PARTY PARK"
	sign.font = Look.title_font()
	sign.font_size = 200
	sign.outline_size = 36
	sign.modulate = UI.LIGHT
	sign.outline_modulate = Color("e5383b")
	sign.pixel_size = 0.012
	sign.position = Vector3(3.5, 2.6, -3.5)
	add_child(sign)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in (6 if Look.fast() else 14):
		var a := rng.randf_range(0.0, TAU)
		var at := Vector3(cos(a) * rng.randf_range(17.5, 19.5), -0.05, sin(a) * rng.randf_range(11.0, 12.5))
		Dressing.prop(self, "nature/tree_palmDetailedTall" if k % 2 == 0 else "nature/plant_bushLarge", at, rng.randf_range(0, 360), 3.4 if k % 2 == 0 else 3.0)
	for k in 6:
		var at := Vector3(rng.randf_range(-8.0, 8.0), 0.0, rng.randf_range(-4.5, 4.5))
		if at.distance_to(Vector3(-1.5, 0, -1)) > 3.5:
			Dressing.prop(self, ["nature/flower_redA", "nature/flower_yellowA", "nature/flower_purpleA"][k % 3], at, k * 50.0, 4.0)
	if Look.fast():
		Look.no_shadow(self)


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
	var dice := Label3D.new()
	dice.font = Look.title_font()
	dice.font_size = 110
	dice.outline_size = 26
	dice.outline_modulate = UI.DARK
	dice.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dice.no_depth_test = true
	dice.pixel_size = 0.008
	dice.position.y = 2.3
	root.add_child(dice)
	_pieces[pid] = {root = root, model = model, dice = dice, path = []}
	if not Net.party.is_empty():
		_place(pid, Net.party)


func _popup(pos: Vector3, text: String, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = Look.title_font()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 80
	l.outline_size = 20
	l.pixel_size = 0.007
	l.modulate = col
	l.outline_modulate = UI.DARK
	add_child(l)
	l.position = pos
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "position", pos + Vector3.UP * 1.4, 1.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(1.3)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.4).set_delay(1.3)
	tw.chain().tween_callback(l.queue_free)


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
	_cards = VBoxContainer.new()
	_cards.position = Vector2(18, 18)
	_cards.add_theme_constant_override("separation", 6)
	_ui.add_child(_cards)
	_roll = UI.primary(UI.button(_ui, "Roll!", func(): Net.party_roll(), 300))
	_roll.add_theme_font_size_override("font_size", 48)
	_roll.custom_minimum_size.y = 88
	_roll.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_roll.offset_top = -130
	_roll.offset_bottom = -42
	_roll.grow_horizontal = Control.GROW_DIRECTION_BOTH
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
	_round.text = "Round %d of %d" % [mini(s.round, s.rounds), s.rounds] if s.phase != "final" else "Party over!"
	var present: Array = s.players.keys().filter(func(pid): return Net.players.has(pid))
	match s.phase:
		"roll":
			var waiting := Party.waiting_on(s, present).size()
			var last := ""
			if not s.result.is_empty() and Net.players.has(s.result[0][0]):
				last = "%s won %s  ·  " % [Net.players[s.result[0][0]].name, Party.MINIGAMES[s.last_game].name]
			_sub.text = last + ("Everyone roll!" if waiting == present.size() else "Waiting on %d..." % waiting)
		"move":
			_sub.text = "Hop hop hop..."
		"intro":
			_sub.text = "Get ready!"
		_:
			_sub.text = ""
	_roll.visible = s.phase == "roll" and s.players.has(Net.my_id()) and not s.rolls.has(Net.my_id())
	for c in _cards.get_children():
		c.queue_free()
	var rank := 0
	for pid in Party.standings(s):
		if not Net.players.has(pid):
			continue
		rank += 1
		var p: Dictionary = s.players[pid]
		var card := PanelContainer.new()
		var style := UI.card(UI.PAPER if pid != Net.my_id() else UI.CREAM, 16, 3)
		style.border_color = Net.players[pid].color
		style.border_width_left = 10
		style.content_margin_top = 6
		style.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", style)
		card.custom_minimum_size.x = 300
		_cards.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		UI.label(row, str(rank), 22, Color(UI.NAVY, 0.5), true)
		var name := UI.label(row, Net.players[pid].name, 22, UI.ink(Net.players[pid].color), true)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(Icon.new(true))
		UI.label(row, str(p.stars), 22, UI.NAVY, true)
		row.add_child(Icon.new(false))
		UI.label(row, str(p.coins), 22, UI.NAVY, true)


func _unhandled_input(e: InputEvent) -> void:
	if _roll.visible and (e.is_action_pressed("punch") or e.is_action_pressed("jump") or e.is_action_pressed("ui_accept")):
		Net.party_roll()


func _show_final(s: Dictionary) -> void:
	var v: VBoxContainer = _final.get_node("V")
	for c in v.get_children():
		c.queue_free()
	var order := Party.standings(s).filter(func(pid): return Net.players.has(pid))
	if order.is_empty():
		return
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
