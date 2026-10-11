extends Node
## Title screen, customization, settings and lobby. Starts and frees the match.
## Command-line args after `--` drive tests: --host --join=IP --name=N --bots=N --seconds=S --autostart
## --quit-after=S --shot=out.png@5,9 --timescale=N --screen=customize|settings|join

var _game: Game
var _attract: Node3D
var _attract_arena: Arena
var _attract_bots: Array[Beast] = []
var _attract_cam: Camera3D
var _ui: Control
var _screens := {}
var _status: Label
var _cards: GridContainer
var _length: OptionButton
var _host_only: Array[Control] = []
var _ip: LineEdit
var _name: LineEdit
var _preview: BowlerModel
var _preview_holder: Control
var _slot_labels := {}
var _preset := 0
var _args := {}
var _logo_node: Control


func _ready() -> void:
	_input_map()
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _args.has("name"):
		Prefs.player_name = _args.name
	_build_ui()
	_show_attract(true)
	Net.players_changed.connect(_refresh_lobby)
	Net.match_started.connect(_on_match_started)
	Net.match_ended.connect(_on_match_ended)
	Net.status.connect(func(t):
		_status.text = t
		_show("main"))
	Music.play("menu", 0.0)
	_show(_args.get("screen", "main"))
	_run_args()


func _input_map() -> void:
	var keys := {up = [KEY_W, KEY_UP], down = [KEY_S, KEY_DOWN], left = [KEY_A, KEY_LEFT], right = [KEY_D, KEY_RIGHT],
		jump = [KEY_SPACE], punch = [KEY_J], grab = [KEY_K], dive = [KEY_SHIFT, KEY_L], pause = [KEY_ESCAPE]}
	var pad := {jump = [JOY_BUTTON_A], punch = [JOY_BUTTON_X], grab = [JOY_BUTTON_RIGHT_SHOULDER], dive = [JOY_BUTTON_B], pause = [JOY_BUTTON_START]}
	var axes := {left = [JOY_AXIS_LEFT_X, -1.0], right = [JOY_AXIS_LEFT_X, 1.0], up = [JOY_AXIS_LEFT_Y, -1.0],
		down = [JOY_AXIS_LEFT_Y, 1.0], punch = [JOY_AXIS_TRIGGER_RIGHT, 1.0], grab = [JOY_AXIS_TRIGGER_LEFT, 1.0]}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		for k in keys[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)
		for b in pad.get(action, []):
			var e := InputEventJoypadButton.new()
			e.button_index = b
			InputMap.action_add_event(action, e)
		if axes.has(action):
			var e := InputEventJoypadMotion.new()
			e.axis = axes[action][0]
			e.axis_value = axes[action][1]
			InputMap.action_add_event(action, e)
	for pair in [["punch", MOUSE_BUTTON_LEFT], ["grab", MOUSE_BUTTON_RIGHT]]:
		var e := InputEventMouseButton.new()
		e.button_index = pair[1]
		InputMap.action_add_event(pair[0], e)


# ================================================================= screens

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UI.theme()
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)
	var shade := TextureRect.new()  # darken the left side so the menu reads over the live scene
	var grad := GradientTexture2D.new()
	grad.gradient = Gradient.new()
	grad.gradient.set_color(0, Color(0.04, 0.01, 0.1, 0.85))
	grad.gradient.set_color(1, Color(0.04, 0.01, 0.1, 0.0))
	grad.fill_to = Vector2(1, 0)
	shade.texture = grad
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.offset_right = 900
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)

	var col := VBoxContainer.new()
	col.position = Vector2(70, 30)
	col.add_theme_constant_override("separation", 14)
	_ui.add_child(col)
	_logo(col)
	var stack := Control.new()  # screens swap in here
	stack.custom_minimum_size = Vector2(560, 540)
	col.add_child(stack)
	_status = UI.label(col, "", 20, Color(1, 1, 1, 0.8))
	_status.custom_minimum_size.x = 640
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var main := _screen(stack, "main")
	UI.button(main, "HOST GAME", func():
		_status.text = Net.host()
		if Net.is_host():
			_show("lobby"))
	UI.button(main, "JOIN GAME", func(): _show("join"))
	UI.button(main, "CUSTOMIZE", func(): _show("customize"))
	UI.button(main, "SETTINGS", func(): _show("settings"))
	UI.button(main, "QUIT", func(): get_tree().quit())

	var join := _screen(stack, "join", "JOIN A FRIEND")
	UI.label(join, "Host's IP address", 22, UI.CYAN)
	_ip = LineEdit.new()
	_ip.text = "127.0.0.1"
	_ip.custom_minimum_size = Vector2(420, 54)
	join.add_child(_ip)
	UI.button(join, "JOIN", func():
		_status.text = "Connecting..."
		var err := Net.join(_ip.text)
		if err != "":
			_status.text = err)
	UI.button(join, "BACK", func(): _show("main"))

	_build_customize(stack)
	_build_settings(stack)

	var lobby := _screen(stack, "lobby", "LOBBY")
	_cards = GridContainer.new()
	_cards.columns = 2
	_cards.add_theme_constant_override("h_separation", 12)
	_cards.add_theme_constant_override("v_separation", 10)
	lobby.add_child(_cards)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	lobby.add_child(row)
	_host_only.append(UI.button(row, "+ BOT", Net.add_bot, 130))
	_host_only.append(UI.button(row, "- BOT", Net.remove_bot, 130))
	_length = OptionButton.new()
	for m in [2, 3, 5]:
		_length.add_item("%d MIN MATCH" % m, m)
	_length.select(1)
	_length.custom_minimum_size = Vector2(240, 60)
	row.add_child(_length)
	_host_only.append(_length)
	var start := UI.button(lobby, "START MATCH", func(): Net.start_match(_length.get_selected_id() * 60.0))
	start.add_theme_stylebox_override("normal", UI.box(Color("c79a00"), UI.YELLOW))
	_host_only.append(start)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	lobby.add_child(row2)
	UI.button(row2, "CUSTOMIZE", func(): _show("customize"), 230)
	UI.button(row2, "SETTINGS", func(): _show("settings"), 200)
	UI.button(row2, "LEAVE", func():
		Net.leave()
		_show("main"), 160)


func _logo(parent: Node) -> void:
	var logo := Control.new()
	logo.custom_minimum_size = Vector2(640, 230)
	parent.add_child(logo)
	_logo_node = logo
	var a := UI.label(logo, "BOWLING", 120, UI.YELLOW, true)
	a.add_theme_color_override("font_outline_color", Color("ff2d95"))
	a.add_theme_constant_override("outline_size", 28)
	a.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	a.add_theme_constant_override("shadow_offset_y", 8)
	var b := UI.label(logo, "YOUR FRIENDS", 74, UI.CYAN, true)
	b.add_theme_color_override("font_outline_color", Color("3a0f7a"))
	b.add_theme_constant_override("outline_size", 22)
	b.position = Vector2(40, 120)
	var tag := UI.label(logo, "Beat them into a ball. Then bowl them.", 24, Color.WHITE)
	tag.position = Vector2(46, 200)
	logo.pivot_offset = Vector2(300, 110)
	logo.rotation = -0.04
	var tw := logo.create_tween().set_loops()  # gentle bob, like an arcade attract screen
	tw.tween_property(logo, "scale", Vector2.ONE * 1.03, 1.2).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(logo, "rotation", -0.02, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(logo, "scale", Vector2.ONE, 1.2).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(logo, "rotation", -0.05, 1.2).set_trans(Tween.TRANS_SINE)


func _screen(parent: Control, id: String, title := "") -> VBoxContainer:
	var v: VBoxContainer
	if title == "":
		v = VBoxContainer.new()
		v.add_theme_constant_override("separation", 14)
		parent.add_child(v)
		_screens[id] = v
	else:
		v = UI.panel(parent, title)
		_screens[id] = v.get_parent()
	return v


func _show(id: String) -> void:
	for k in _screens:
		_screens[k].visible = k == id
	if _screens.has(id):
		UI.pop_in.call_deferred(_screens[id])
	_preview_holder.visible = id == "customize"
	_logo_node.visible = id in ["main", "join"]  # sub-screens need the room
	if id == "lobby":
		_refresh_lobby()


func _build_customize(stack: Control) -> void:
	var v := _screen(stack, "customize", "CUSTOMIZE")
	_name = LineEdit.new()
	_name.text = Prefs.player_name
	_name.max_length = 16
	_name.placeholder_text = "Your name"
	_name.custom_minimum_size = Vector2(420, 50)
	_name.text_changed.connect(func(t):
		Prefs.player_name = t.strip_edges() if t.strip_edges() != "" else "Bowler"
		_saved(false))
	v.add_child(_name)
	_slot_row(v, "preset", "Look")
	for slot in Skins.SLOTS:
		_slot_row(v, slot, Skins.LABELS[slot])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	UI.button(row, "RANDOM", func():
		Prefs.skin = Skins.random_skin()
		_saved(), 200)
	UI.button(row, "DONE", func(): _show("lobby" if Net.is_online() else "main"), 200)

	# Turntable preview on the right half of the screen.
	_preview_holder = Control.new()
	_preview_holder.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_preview_holder.offset_left = -820
	_preview_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_preview_holder)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_holder.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8a70ff")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.4
	vp.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.5, 2.0, -2.0)
	rim.light_color = UI.PINK
	rim.light_energy = 4.0
	rim.omni_range = 6.0
	vp.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 40.0
	vp.add_child(cam)
	cam.fov = 34.0
	cam.look_at_from_position(Vector3(0, 0.7, 5.6), Vector3(0, 0.15, 0))
	var disc := CylinderMesh.new()
	disc.top_radius = 0.9
	disc.bottom_radius = 0.95
	disc.height = 0.12
	Look.mesh(vp, disc, Look.toy(Color("2a1460"), 0.4), Vector3(0, -0.92, 0))
	var glow := TorusMesh.new()
	glow.inner_radius = 0.9
	glow.outer_radius = 0.97
	Look.mesh(vp, glow, Look.neon(UI.CYAN, 3.0), Vector3(0, -0.86, 0))
	_preview = BowlerModel.new()
	vp.add_child(_preview)
	_preview.build(_my_color(), Prefs.skin)
	_refresh_slots()


func _slot_row(parent: Node, slot: String, title: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var name := UI.label(row, title.to_upper(), 22, UI.CYAN)
	name.custom_minimum_size.x = 110
	UI.button(row, "<", func(): _cycle(slot, -1), 54).custom_minimum_size.y = 42
	var value := UI.label(row, "", 24, Color.WHITE, true)
	value.custom_minimum_size.x = 240
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.button(row, ">", func(): _cycle(slot, 1), 54).custom_minimum_size.y = 42
	_slot_labels[slot] = value


func _cycle(slot: String, step: int) -> void:
	if slot == "preset":
		_preset = (_preset + step + Skins.PRESETS.size()) % Skins.PRESETS.size()
		Prefs.skin = Skins.PRESETS.values()[_preset].duplicate()
	else:
		Skins.cycle(Prefs.skin, slot, step)
	_saved()


func _saved(rebuild := true) -> void:
	Prefs.save()
	Net.update_me()
	if rebuild:
		_preview.build(_my_color(), Prefs.skin)
		_preview.hit(Vector3.FORWARD, 0.4)  # a little hop on every change
	_refresh_slots()


func _refresh_slots() -> void:
	for slot in _slot_labels:
		if slot == "preset":
			var i := Skins.PRESETS.values().find(Prefs.skin)
			_slot_labels[slot].text = Skins.PRESETS.keys()[i] if i >= 0 else "Custom"
		else:
			_slot_labels[slot].text = Skins.pretty(Prefs.skin[slot])


func _my_color() -> Color:
	return Net.players[Net.my_id()].color if Net.players.has(Net.my_id()) else Net.COLORS[0]


func _build_settings(stack: Control) -> void:
	var v := _screen(stack, "settings", "SETTINGS")
	for pair in [["MUSIC", "music"], ["SOUND FX", "sfx"]]:
		UI.label(v, pair[0], 22, UI.CYAN)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.value = Prefs.get(pair[1])
		s.custom_minimum_size = Vector2(420, 32)
		s.value_changed.connect(func(x):
			Prefs.set(pair[1], x)
			Prefs.apply())
		s.drag_ended.connect(func(_c): Sfx.play_ui("ui_click", -4.0))
		v.add_child(s)
	var fs := CheckButton.new()
	fs.text = "FULLSCREEN"
	fs.button_pressed = Prefs.fullscreen
	fs.toggled.connect(func(on):
		Prefs.fullscreen = on
		Prefs.apply())
	v.add_child(fs)
	UI.button(v, "BACK", func():
		Prefs.save()
		_show("lobby" if Net.is_online() else "main"))


func _refresh_lobby() -> void:
	if Net.players.is_empty():
		return
	if _screens.main.visible or _screens.join.visible:
		_show("lobby")
	for c in _cards.get_children():
		c.queue_free()
	for id in Net.players:
		var p: Dictionary = Net.players[id]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UI.box(Color(0.06, 0.03, 0.14, 0.92), p.color, 4, 14))
		card.custom_minimum_size = Vector2(300, 72)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		card.add_child(v)
		UI.label(v, p.name, 28, p.color.lightened(0.25), true)
		var tags := []
		if id == 1:
			tags.append("HOST")
		if p.bot:
			tags.append("BOT")
		if id == Net.my_id():
			tags.append("YOU")
		var look := Skins.PRESETS.values().find(p.skin)
		tags.append(Skins.PRESETS.keys()[look] if look >= 0 else "%s · %s" % [Skins.pretty(p.skin.hat), Skins.pretty(p.skin.outfit)])
		UI.label(v, "  ·  ".join(tags), 17, Color(1, 1, 1, 0.7))
		_cards.add_child(card)
	for c in _host_only:
		c.visible = Net.is_host()
	if Net.is_host():
		var ips := Array(IP.get_local_addresses()).filter(func(a): return a.count(".") == 3 and not a.begins_with("127."))
		_status.text = "Friends join with your IP: %s (port %d)\nOver the internet: forward UDP %d, or use a LAN VPN like Tailscale." \
			% [", ".join(ips.slice(0, 3)), Net.PORT, Net.PORT]
	elif Net.is_online():
		_status.text = "Waiting for the host to start..."
	_preview.build(_my_color(), Prefs.skin)


# ================================================================= attract scene: bots playing behind the menu

func _show_attract(on: bool) -> void:
	if on and _attract == null:
		_attract = Node3D.new()
		add_child(_attract)
		_attract_arena = Arena.new()
		_attract.add_child(_attract_arena)
		_attract_arena.setup(true)
		_attract_arena.screen_board.set_rows([{name = "INSERT FRIENDS", color = UI.PINK, total = 300, rolls = ["X", "X", "X", "X", "X", "X", "X", "X", "X", "X"]}], 0.0)
		_attract_bots.clear()
		for i in 4:
			var b := Beast.new()
			_attract.add_child(b)
			b.setup(-100 - i, {name = Net.BOT_NAMES[i], color = Net.COLORS[i + 1], skin = Skins.PRESETS.values()[i + 1]}, _attract_arena, true)
			b.global_position = _attract_arena.spawn_point(i)
			_attract_bots.append(b)
		_attract_cam = Camera3D.new()
		_attract_cam.fov = 55.0
		_attract_cam.position = Vector3(3, 5, 14)
		_attract.add_child(_attract_cam)
		_attract_cam.current = true
	elif not on and _attract:
		_attract.queue_free()
		_attract = null
		_attract_bots.clear()


func _physics_process(dt: float) -> void:
	if _attract == null:
		return
	for b in _attract_bots:
		b.sim(Bot.think(b, _attract_arena, dt), dt)
	_attract_arena.server_update(dt, _attract_bots)


func _process(dt: float) -> void:
	if _preview_holder.visible:
		_preview.rotation.y = PI + sin(Time.get_ticks_msec() * 0.0007) * 0.6  # face the camera, sway a little
		_preview.pose(dt, {dance = true})
	if _attract == null:
		return
	var focus := Vector3.ZERO
	for b in _attract_bots:
		focus += b.global_position / _attract_bots.size()
	var t := Time.get_ticks_msec() * 0.0001
	var want := Vector3(clampf(focus.x, -4, 4) + 2.5 + sin(t) * 2.0, 5.0, clampf(focus.z, -6, 8) + 9.0)
	_attract_cam.position = _attract_cam.position.lerp(want, 1.0 - exp(-dt * 0.8))
	_attract_cam.look_at(Vector3(focus.x * 0.5 + 1.5, 0.5, focus.z - 6.0))


func _on_match_started(_seconds: float) -> void:
	if _game:
		return
	_show_attract(false)
	_ui.visible = false
	_game = Game.new()
	_game.name = "Game"  # RPC paths must match on every peer
	add_child(_game)


func _on_match_ended() -> void:
	if _game:
		_game.queue_free()
		_game = null
	_show_attract(true)
	_ui.visible = true
	Music.play("menu")
	_show("lobby" if Net.is_online() else "main")


# ================================================================= test hooks

func _run_args() -> void:
	if _args.has("timescale"):
		# Scale the tick rate too, so each physics step stays 1/60 s (big steps make bodies tunnel).
		Engine.time_scale = float(_args.timescale)
		Engine.physics_ticks_per_second = int(60 * Engine.time_scale)
		Engine.max_physics_steps_per_frame = 64
	if _args.has("host"):
		_status.text = Net.host()
		_show("lobby")
		for i in int(_args.get("bots", "0")):
			Net.add_bot()
		if _args.has("autostart"):
			Net.start_match(float(_args.get("seconds", "180")))
	elif _args.has("join"):
		Net.join(_args.join)
	if _args.has("shot"):  # --shot=out.png@5,9 saves out_5.png and out_9.png (real seconds)
		var parts: PackedStringArray = _args.shot.split("@")
		for when in (parts[1] if parts.size() > 1 else "3").split(","):
			var path := parts[0].get_basename() + "_" + when + ".png"
			get_tree().create_timer(float(when), true, false, true).timeout.connect(func():
				get_viewport().get_texture().get_image().save_png(path)
				print("SHOT ", path))
	if _args.has("quit-after"):
		get_tree().create_timer(float(_args["quit-after"]), true, false, true).timeout.connect(func():
			_report()
			get_tree().quit())


func _report() -> void:
	var out := {online = Net.is_online(), players = Net.players.size(), in_match = _game != null,
		ms_process = snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		ms_physics = snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
		fps = Performance.get_monitor(Performance.TIME_FPS), nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}
	if _game:
		out.time_left = snappedf(_game.time_left, 0.1)
		out.scores = _game.scores
		out.snapshots = _game._snaps.size()
		out.beast_states = _game.beasts.values().map(func(b): return [b.display_name, b.state, snappedf(b.health, 1), b.global_position.snapped(Vector3(0.1, 0.1, 0.1)), b.skin.hat])
	print("REPORT ", JSON.stringify(out, "", false))
