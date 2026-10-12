extends Node
## Title screen, customization, settings and lobby. Starts and frees the match.
## Command-line args after `--` drive tests: --host --join=IP --name=N --bots=N --seconds=S --autostart
## --quit-after=S --shot=out.png@5,9 --timescale=N --screen=customize|settings|join --map=classic|sunset

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
var _name: LineEdit
var _preview: BowlerModel
var _preview_holder: Control
var _slot_labels := {}
var _preset := 0
var _browse := {}  # slot -> a locked option being previewed (never saved to your skin)
var _lock_hint: Label
var _level_label: Label
var _trophies: VBoxContainer
var _post: CanvasLayer
var _gfx: CheckButton
var _perf := Vector3.ZERO  # first-launch frame-rate check: seconds watched, frames counted, seconds counted
var _args := {}
var _logo_node: Control
var _code: LineEdit
var _lan_list: VBoxContainer
var _lan_empty: Label
var _room_card: PanelContainer
var _room_code: Label
var _conn_msg: Label
var _conn_t := 0.0
var _room_title: Label
var _room_note: Label
var _back_to := "main"
var _conn_ip := ""  # set while joining by IP (not through the online server)
var _hosting := false  # waiting for an online room; fall back to hosting by IP if the server can't be reached


func _ready() -> void:
	_input_map()
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if _args.has("name"):
		Prefs.player_name = _args.name
	_build_ui()
	_show_attract(true)
	_post = Look.post_layer()
	add_child(_post)
	_post.visible = Look.high()
	Net.players_changed.connect(_refresh_lobby)
	Net.match_started.connect(_on_match_started)
	Net.match_ended.connect(_on_match_ended)
	Net.status.connect(func(t):
		if _hosting:  # the online server isn't reachable: host by IP instead, without asking
			_hosting = false
			var err := Net.host_lan()
			if err == "":
				_show("lobby")
				return
			t = err
		_status.text = t
		_show(_back_to))
	Net.room_ready.connect(func(_c):
		_hosting = false
		_show("lobby"))
	Net.direct_info_changed.connect(_refresh_lobby)
	Net.lan_games_changed.connect(_refresh_lan)
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
	if OS.has_feature("mobile"):
		return  # touches are emulated as mouse clicks; on phones the on-screen buttons do this instead
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
	var version := UI.label(_ui, "v" + str(ProjectSettings.get_setting("application/config/version", "")), 16, Color(1, 1, 1, 0.45))
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -120
	version.offset_top = -36
	_status.custom_minimum_size.x = 640
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var main := _screen(stack, "main")
	UI.button(main, "HOST GAME", _host_online)
	UI.button(main, "JOIN GAME", func(): _show("join"))
	UI.button(main, "CUSTOMIZE", func(): _show("customize"))
	UI.button(main, "TROPHIES", func(): _show("trophies"))
	UI.button(main, "SETTINGS", func(): _show("settings"))
	UI.button(main, "QUIT", func(): get_tree().quit())

	var join := _screen(stack, "join", "JOIN A GAME")
	UI.label(join, "TYPE THE CODE OR IP YOUR FRIEND GAVE YOU", 22, UI.CYAN)
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 12)
	join.add_child(code_row)
	_code = LineEdit.new()
	_code.max_length = 21
	_code.placeholder_text = "CODE / IP"
	_code.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code.custom_minimum_size = Vector2(320, 84)
	_code.add_theme_font_override("font", Look.title_font())
	_code.add_theme_font_size_override("font_size", 44)
	_code.text_changed.connect(func(t):
		var up: String = t.to_upper().replace(" ", "")
		if up != t:
			_code.text = up
			_code.caret_column = up.length()
		if _is_code(up):
			_join_code())  # no need to press anything once the code is in
	_code.text_submitted.connect(func(_t): _join_code())
	code_row.add_child(_code)
	UI.button(code_row, "JOIN", _join_code, 150).custom_minimum_size.y = 84
	UI.label(join, "GAMES ON YOUR WI-FI", 22, UI.CYAN)
	_lan_list = VBoxContainer.new()
	_lan_list.add_theme_constant_override("separation", 8)
	join.add_child(_lan_list)
	_lan_empty = UI.label(join, "Looking for games nearby...", 20, Color(1, 1, 1, 0.6))
	UI.button(join, "BACK", func(): _show("main"))

	var conn := _screen(stack, "connecting", "CONNECTING")
	_conn_msg = UI.label(conn, "", 24, Color.WHITE)
	_conn_msg.custom_minimum_size.x = 460
	_conn_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.button(conn, "CANCEL", func():
		Net.leave()
		_show(_back_to))

	_build_customize(stack)
	_build_settings(stack)
	_trophies = _screen(stack, "trophies", "TROPHIES")

	var lobby := _screen(stack, "lobby", "LOBBY")
	_room_card = PanelContainer.new()
	_room_card.add_theme_stylebox_override("panel", UI.box(Color(0.1, 0.05, 0.25, 0.95), UI.YELLOW, 4, 16))
	lobby.add_child(_room_card)
	var rc := HBoxContainer.new()
	rc.add_theme_constant_override("separation", 18)
	_room_card.add_child(rc)
	var rcv := VBoxContainer.new()
	rcv.add_theme_constant_override("separation", -6)
	rc.add_child(rcv)
	_room_title = UI.label(rcv, "ROOM CODE", 20, UI.CYAN, true)
	_room_code = UI.label(rcv, "", 64, UI.YELLOW, true)
	var copy := UI.button(rc, "COPY", func(): pass, 130)
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(_room_code.text)
		copy.text = "COPIED!"
		get_tree().create_timer(1.5).timeout.connect(func(): copy.text = "COPY"))
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_room_note = UI.label(lobby, "", 17, Color(1, 1, 1, 0.75))
	_room_note.custom_minimum_size.x = 600
	_room_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	var maps := OptionButton.new()
	for id in Arena.MAPS:
		maps.add_item(Arena.MAPS[id])
	maps.select(Arena.MAPS.keys().find(Net.map))
	maps.item_selected.connect(func(i): Net.map = Arena.MAPS.keys()[i])
	maps.custom_minimum_size = Vector2(260, 60)
	row.add_child(maps)
	_host_only.append(maps)
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
	if id == "join":
		Net.start_discovery()
		_refresh_lan()
		var clip := DisplayServer.clipboard_get().strip_edges().to_upper()
		if _code.text == "" and (_is_code(clip) or (clip.count(".") == 3 and clip.length() <= 21)):
			_code.text = clip  # a friend pasted the code/IP in chat and you copied it
	elif id != "connecting":
		Net.stop_discovery()
	_logo_node.visible = id in ["main", "join"]  # sub-screens need the room
	if id == "lobby":
		_refresh_lobby()
	if id == "customize":
		_browse.clear()
		_saved(true, false)
	if id == "trophies":
		_refresh_trophies()


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
	_level_label = UI.label(v, "", 20, UI.YELLOW, true)
	_slot_row(v, "preset", "Look")
	for slot in Skins.SLOTS:
		_slot_row(v, slot, Skins.LABELS[slot])
	_lock_hint = UI.label(v, "", 19, Color(1, 1, 1, 0.8))
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


func _refresh_trophies() -> void:
	## Level, the next level reward, and every achievement with what it unlocks.
	for c in _trophies.get_children().slice(1):  # keep the panel title
		c.queue_free()
	var info := Progress.level_info(Prefs.xp)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	_trophies.add_child(top)
	UI.label(top, "LEVEL %d" % info.level, 30, UI.YELLOW, true)
	var bar := UI.bar(top, UI.YELLOW, 260, 20)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.value = 100.0 * info.into / info.need
	UI.label(top, "%d / %d XP" % [info.into, info.need], 18, Color(1, 1, 1, 0.75))
	for lvl in Progress.LEVEL_REWARDS:
		if lvl > info.level:
			UI.label(_trophies, "Level %d unlocks: %s" % [lvl, Progress.reward_name(Progress.LEVEL_REWARDS[lvl])], 19, UI.PINK)
			break
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_trophies.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var done := 0
	for id: String in Progress.ACHIEVEMENTS:
		var a: Dictionary = Progress.ACHIEVEMENTS[id]
		var have: bool = Prefs.achievements.has(id)
		done += int(have)
		var row := HBoxContainer.new()
		list.add_child(row)
		var name := UI.label(row, ("DONE  " if have else "") + a.name, 22, UI.YELLOW if have else Color.WHITE, true)
		name.custom_minimum_size.x = 250
		UI.label(row, Progress.reward_name(a.reward) if a.has("reward") else "+%d XP" % (a.xp + Progress.ACHIEVEMENT_XP), 18, UI.PINK)
		UI.label(list, "      " + a.desc, 17, Color(1, 1, 1, 0.6 if have else 0.8))
	UI.label(_trophies, "%d / %d achievements" % [done, Progress.ACHIEVEMENTS.size()], 18, UI.CYAN)
	UI.button(_trophies, "BACK", func(): _show("main"), 200)


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
		var opts: Array = Skins.SLOTS[slot]
		var next: String = opts[(opts.find(_browse.get(slot, Prefs.skin[slot])) + step + opts.size()) % opts.size()]
		_browse.clear()
		if Progress.lock_reason(slot, next) == "":
			Prefs.skin[slot] = next
		else:
			_browse[slot] = next  # try it on in the preview; your saved look stays as it was
	_saved()


func _saved(rebuild := true, hop := true) -> void:
	Prefs.save()
	Net.update_me()
	if rebuild:
		_preview.build(_my_color(), Prefs.skin.merged(_browse, true))
		if hop:
			_preview.hit(Vector3.FORWARD, 0.4)  # a little hop on every change
	_refresh_slots()


func _refresh_slots() -> void:
	for slot in _slot_labels:
		if slot == "preset":
			var i := Skins.PRESETS.values().find(Prefs.skin)
			_slot_labels[slot].text = Skins.PRESETS.keys()[i] if i >= 0 else "Custom"
		else:
			_slot_labels[slot].text = Skins.pretty(_browse.get(slot, Prefs.skin[slot])) + ("  (LOCKED)" if _browse.has(slot) else "")
			_slot_labels[slot].add_theme_color_override("font_color", Color(1, 1, 1, 0.45) if _browse.has(slot) else Color.WHITE)
	var info := Progress.level_info(Prefs.xp)
	_level_label.text = "LEVEL %d  ·  %d / %d XP" % [info.level, info.into, info.need]
	_lock_hint.text = "" if _browse.is_empty() else "LOCKED: " + Progress.lock_reason(_browse.keys()[0], _browse.values()[0])


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
	UI.label(v, "ONLINE SERVER (leave empty for the default)", 18, UI.CYAN)
	var relay := LineEdit.new()
	relay.text = Prefs.relay
	relay.placeholder_text = Net.DEFAULT_RELAY
	relay.custom_minimum_size = Vector2(460, 44)
	relay.add_theme_font_size_override("font_size", 16)
	relay.text_changed.connect(func(t): Prefs.relay = t.strip_edges())
	v.add_child(relay)
	var fs := CheckButton.new()
	fs.text = "FULLSCREEN"
	fs.button_pressed = Prefs.fullscreen
	fs.toggled.connect(func(on):
		Prefs.fullscreen = on
		Prefs.apply())
	v.add_child(fs)
	_gfx = CheckButton.new()
	_gfx.text = "HIGH-END GRAPHICS (turn off if it's slow)"
	_gfx.button_pressed = Prefs.graphics == "high"
	_gfx.toggled.connect(_set_graphics)
	v.add_child(_gfx)
	UI.button(v, "BACK", func():
		Prefs.save()
		_show("lobby" if Net.is_online() else "main"))


func _set_graphics(on: bool) -> void:
	Prefs.graphics = "high" if on else "classic"
	Prefs.graphics_checked = true  # the player chose: never second-guess it
	Prefs.apply()
	Prefs.save()
	Arena._pin_mat = null  # cached materials are rebuilt with the new look
	Powerups._ball_mesh = null
	_post.visible = on
	_gfx.set_pressed_no_signal(on)
	if _game == null:
		_show_attract(false)
		_show_attract(true)


func _check_performance(dt: float) -> void:
	## First launch on High: watch the menu for a few seconds. Too slow for a good first impression? Go Classic.
	if Prefs.graphics_checked or not Look.high() or _args.has("shot") or DisplayServer.get_name() == "headless":
		return
	_perf.x += dt
	if _perf.x > 3.0:  # skip the loading hitch
		_perf.y += 1.0
		_perf.z += dt
	if _perf.x > 9.0:
		var fps := _perf.y / _perf.z
		if fps < 35.0:
			_set_graphics(false)
			_toast("Switched to Classic graphics so the game runs smoothly (%d fps). Change it in SETTINGS." % fps)
		else:
			Prefs.graphics_checked = true
			Prefs.save()


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
	var lan := Array(IP.get_local_addresses()).filter(func(a): return a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."))
	_status.text = ""
	_room_note.text = ""
	if Net.room_code != "":
		_room_card.visible = true
		_room_title.text = "ROOM CODE"
		_room_code.text = Net.room_code
		_room_code.add_theme_font_size_override("font_size", 64)
		_room_note.text = "Friends press JOIN GAME and type the code. Anyone on your Wi-Fi also sees your game listed there." \
			if Net.is_host() else "Waiting for the host to start..."
	elif Net.is_host():
		_room_card.visible = true
		_room_title.text = "YOUR IP: FRIENDS TYPE THIS IN JOIN GAME"
		_room_code.text = Net.public_ip if Net.public_ip != "" else "finding..."
		_room_code.add_theme_font_size_override("font_size", 46)
		var router: String = {0: "Asking your router to open the game port...", 1: "Your router opened the game port automatically.",
			-1: "Your router didn't open the port automatically: forward UDP %d to this PC so friends outside your Wi-Fi can join." % Net.PORT}[Net.port_open]
		if Net.shared_ip:
			router = "Your internet provider shares your IP, so friends outside your Wi-Fi can't join by IP. Set up the online server (room codes) for that."
		_room_note.text = "FRIENDS ON YOUR WI-FI: type %s\nFRIENDS ELSEWHERE: type the IP above. %s\nNobody can get in? Allow \"Bowling your Friends\" in Windows Firewall (tick Private AND Public)." \
			% [lan[0] if not lan.is_empty() else "-", router]
	else:
		_room_card.visible = false
		if Net.is_online():
			_room_note.text = "Waiting for the host to start..."
	_preview.build(_my_color(), Prefs.skin)


func _host_online() -> void:
	_back_to = "main"
	_hosting = true
	_connecting("Creating your room...")
	Net.host_online()


func _is_code(s: String) -> bool:
	return s.length() == 4 and s.is_valid_identifier() and not s.contains("_")


func _join_code() -> void:
	## One box for both: a 4-letter room code goes through the online server, anything else is treated as an IP.
	var text := _code.text.strip_edges().to_upper()
	_back_to = "join"
	if _is_code(text):
		_connecting("Joining %s..." % text)
		Net.join_code(text)
	elif text.count(".") == 3 or text.contains(":"):
		_connecting("Connecting to %s..." % text, text)
		var err := Net.join_ip(text)
		if err != "":
			_status.text = err
			_show("join")
	else:
		_status.text = "Type the 4-letter code (like BRKT) or the IP (like 73.21.140.9) your friend gave you."


func _connecting(msg: String, ip := "") -> void:
	_conn_ip = ip
	_status.text = ""
	_conn_msg.text = msg
	_conn_t = 0.0
	_show("connecting")


func _refresh_lan() -> void:
	for c in _lan_list.get_children():
		c.queue_free()
	for ip in Net.lan_games:
		var g: Dictionary = Net.lan_games[ip]
		var code: String = g.get("code", "")
		var b := UI.button(_lan_list, "%s'S GAME  ·  %d PLAYER%s" % [str(g.name).to_upper(), g.n, "" if g.n == 1 else "S"], func():
			if code != "":
				_code.text = code
				_join_code()
			else:
				_back_to = "join"
				_connecting("Connecting to %s..." % ip, ip)
				Net.join_ip(ip), 460)
		b.add_theme_font_size_override("font_size", 22)
	_lan_empty.visible = Net.lan_games.is_empty()


# ================================================================= attract scene: bots playing behind the menu

func _show_attract(on: bool) -> void:
	if on and _attract == null:
		_attract = Node3D.new()
		add_child(_attract)
		_attract_arena = Arena.make(_args.get("map", Arena.MAPS.keys().pick_random()))
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
		if Look.high():
			Look.dof(_attract_cam, 20.0)
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
	if _screens.connecting.visible:
		_conn_t += dt
		if _conn_t > 4.0 and not Net.is_online():
			_conn_msg.text = ("Waking up the online server...\nThe first game of the day can take up to a minute." if _conn_ip == "" else
				"Still trying %s...\nOn the same Wi-Fi as the host? Use the host's Wi-Fi IP (starts with 192.168 or 10.)." % _conn_ip)
	_check_performance(dt)
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
	if not Progress.fresh.is_empty():
		_toast("NEW UNLOCKS: %s. Try them on in CUSTOMIZE!" % ", ".join(Progress.fresh.map(func(r): return Progress.reward_name(r))))
		Progress.fresh = []


func _toast(text: String) -> void:
	## A note that pops up at the bottom of the screen for a few seconds.
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(0.06, 0.03, 0.14, 0.95), UI.YELLOW, 6, 16))
	UI.label(p, text, 24, UI.YELLOW, true)
	_ui.add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 40)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	UI.pop_in.call_deferred(p)
	var tw := p.create_tween()
	tw.tween_interval(8.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


# ================================================================= test hooks

func _run_args() -> void:
	if _args.has("timescale"):
		# Scale the tick rate too, so each physics step stays 1/60 s (big steps make bodies tunnel).
		Engine.time_scale = float(_args.timescale)
		Engine.physics_ticks_per_second = int(60 * Engine.time_scale)
		Engine.max_physics_steps_per_frame = 64
	if _args.has("relay"):
		Prefs.relay = _args.relay
	if _args.has("map"):
		Net.map = _args.map
	var setup := func():
		for i in int(_args.get("bots", "0")):
			Net.add_bot()
		if _args.has("autostart"):
			Net.start_match(float(_args.get("seconds", "180")))
	if _args.has("host"):  # local network (ENet)
		_status.text = Net.host_lan()
		_show("lobby")
		setup.call()
	elif _args.has("host-online"):
		Net.room_ready.connect(func(_c): setup.call(), CONNECT_ONE_SHOT)
		_host_online()
	elif _args.has("join"):
		Net.join_ip(_args.join)
	elif _args.has("join-code"):
		_code.text = _args["join-code"]
		_join_code()
	if _args.has("discover"):
		_show("join")
		get_tree().create_timer(3.0).timeout.connect(func(): print("LAN GAMES ", JSON.stringify(Net.lan_games)))
	if _args.has("hide-ui"):  # clean background shots for the website
		_ui.visible = false
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
	var out := {online = Net.is_online(), players = Net.players.size(), in_match = _game != null, room = Net.room_code, status = _status.text,
		ms_process = snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		ms_physics = snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
		fps = Performance.get_monitor(Performance.TIME_FPS), nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}
	if _game:
		out.time_left = snappedf(_game.time_left, 0.1)
		out.scores = _game.scores
		out.snapshots = _game._snaps.size()
		out.beast_states = _game.beasts.values().map(func(b): return [b.display_name, b.state, snappedf(b.health, 1), b.global_position.snapped(Vector3(0.1, 0.1, 0.1)), b.skin.hat])
	print("REPORT ", JSON.stringify(out, "", false))
