extends Node
## Title menu and lobby. Starts and frees the match.
## Command-line args after `--` drive headless tests: --host --join=IP --name=N --bots=N
## --seconds=S --autostart --quit-after=S --shot=path.png@S --timescale=N

var _game: Game
var _attract: Node3D
var _ui: Control
var _main_panel: VBoxContainer
var _lobby_panel: VBoxContainer
var _name: LineEdit
var _ip: LineEdit
var _status: Label
var _players: VBoxContainer
var _length: OptionButton
var _start: Button
var _bot_buttons: HBoxContainer
var _args := {}


func _ready() -> void:
	_input_map()
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_build_menu()
	_show_attract(true)
	Net.players_changed.connect(_refresh_lobby)
	Net.match_started.connect(_on_match_started)
	Net.match_ended.connect(_on_match_ended)
	Net.status.connect(func(t):
		_status.text = t
		_show_panel(_main_panel))
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


# ---------------------------------------------------------------- menu

func _build_menu() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.theme = _theme()
	layer.add_child(_ui)
	var box := VBoxContainer.new()
	box.position = Vector2(70, 50)
	box.add_theme_constant_override("separation", 14)
	_ui.add_child(box)
	var title := _label(box, "BOWLING\nYOUR FRIENDS", 72, Color("ffe14d"))
	title.add_theme_color_override("font_outline_color", Color("ff2d95"))
	title.add_theme_constant_override("outline_size", 22)
	_label(box, "Beat them into a ball. Then bowl them.", 26, Color("2de2ff"))

	_main_panel = VBoxContainer.new()
	_main_panel.add_theme_constant_override("separation", 10)
	box.add_child(_main_panel)
	_name = _field(_main_panel, "Your name", _args.get("name", "Bowler%d" % (randi() % 100)))
	_button(_main_panel, "Host game", func(): _act(Net.host(_name.text)))
	_ip = _field(_main_panel, "Host IP", "127.0.0.1")
	_button(_main_panel, "Join game", func():
		_status.text = "Connecting..."
		_act(Net.join(_name.text, _ip.text)))
	_button(_main_panel, "Quit", func(): get_tree().quit())

	_lobby_panel = VBoxContainer.new()
	_lobby_panel.add_theme_constant_override("separation", 10)
	box.add_child(_lobby_panel)
	_label(_lobby_panel, "LOBBY", 34, Color.WHITE)
	_players = VBoxContainer.new()
	_lobby_panel.add_child(_players)
	_bot_buttons = HBoxContainer.new()
	_lobby_panel.add_child(_bot_buttons)
	_button(_bot_buttons, "+ Bot", Net.add_bot).custom_minimum_size.x = 150
	_button(_bot_buttons, "- Bot", Net.remove_bot).custom_minimum_size.x = 150
	_length = OptionButton.new()
	for m in [2, 3, 5]:
		_length.add_item("%d minute match" % m, m)
	_length.select(1)
	_lobby_panel.add_child(_length)
	_start = _button(_lobby_panel, "START MATCH", func(): Net.start_match(_length.get_selected_id() * 60.0))
	_button(_lobby_panel, "Leave", func(): Net.leave(); _show_panel(_main_panel))
	_status = _label(box, "", 20, Color(1, 1, 1, 0.75))
	_show_panel(_main_panel)


func _act(err: String) -> void:
	_status.text = err
	if err == "" and Net.is_host():
		_show_panel(_lobby_panel)
		_refresh_lobby()


func _refresh_lobby() -> void:
	if Net.players.is_empty():
		return
	_show_panel(_lobby_panel)
	for c in _players.get_children():
		c.queue_free()
	for id in Net.players:
		var p: Dictionary = Net.players[id]
		_label(_players, ("[BOT] " if p.bot else "") + p.name + (" (you)" if id == Net.my_id() else ""), 26, p.color)
	_start.visible = Net.is_host()
	_bot_buttons.visible = Net.is_host()
	_length.visible = Net.is_host()
	if Net.is_host():
		var ips := Array(IP.get_local_addresses()).filter(func(a): return a.count(".") == 3 and not a.begins_with("127."))
		_status.text = "Friends join with your IP (port %d): %s\nOver the internet: forward UDP %d, or use a LAN VPN (Tailscale, ZeroTier)." \
			% [Net.PORT, ", ".join(ips.slice(0, 3)), Net.PORT]
	else:
		_status.text = "Waiting for the host to start..."


func _show_panel(p: Control) -> void:
	_main_panel.visible = p == _main_panel
	_lobby_panel.visible = p == _lobby_panel


func _show_attract(on: bool) -> void:
	if on and _attract == null:
		_attract = Node3D.new()
		add_child(_attract)
		var arena := Arena.new()
		_attract.add_child(arena)
		arena.setup(false)
		arena.screen_board.set_rows([{name = "INSERT FRIENDS", color = Color("ff3fb4"), total = 300, rolls = ["X", "X", "X", "X", "X", "X", "X", "X", "X", "X"]}], 0.0)
		var cam := Camera3D.new()
		cam.fov = 60.0
		_attract.add_child(cam)
		cam.current = true
		_attract.set_meta("cam", cam)
	elif not on and _attract:
		_attract.queue_free()
		_attract = null


func _process(_dt: float) -> void:
	if _attract:  # slow orbit over the alley behind the menu
		var t := Time.get_ticks_msec() * 0.00008
		var cam: Camera3D = _attract.get_meta("cam")
		cam.position = Vector3(sin(t) * 5.0 + 2.0, 3.4, 9.0 + cos(t) * 2.0)
		cam.look_at(Vector3(0, 1.5, -12))


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
	_show_panel(_lobby_panel if Net.is_online() else _main_panel)
	_refresh_lobby()


# ---------------------------------------------------------------- widgets

func _theme() -> Theme:
	var t := Theme.new()
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("2a1460")
	normal.set_corner_radius_all(14)
	normal.set_content_margin_all(12)
	normal.border_color = Color("ff3fb4")
	normal.set_border_width_all(2)
	var hover := normal.duplicate()
	hover.bg_color = Color("4a1f9a")
	hover.border_color = Color("ffe14d")
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, hover)
		t.set_stylebox("focus", type, hover)
		t.set_font_size("font_size", type, 26)
	t.set_stylebox("normal", "LineEdit", normal)
	t.set_font_size("font_size", "LineEdit", 24)
	t.set_font_size("font_size", "PopupMenu", 22)
	return t


func _label(parent: Node, text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", maxi(size / 7, 3))
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.1))
	parent.add_child(l)
	return l


func _button(parent: Node, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 56)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _field(parent: Node, placeholder: String, value: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = value
	e.custom_minimum_size = Vector2(320, 50)
	parent.add_child(e)
	return e


# ---------------------------------------------------------------- test hooks

func _run_args() -> void:
	if _args.has("timescale"):
		# Scale the tick rate too, so each physics step stays 1/60 s (big steps make bodies tunnel).
		Engine.time_scale = float(_args.timescale)
		Engine.physics_ticks_per_second = int(60 * Engine.time_scale)
		Engine.max_physics_steps_per_frame = 64
	if _args.has("host"):
		_act(Net.host(_args.get("name", "Host")))
		for i in int(_args.get("bots", "0")):
			Net.add_bot()
		if _args.has("autostart"):
			Net.start_match(float(_args.get("seconds", "180")))
	elif _args.has("join"):
		_act(Net.join(_args.get("name", "Client"), _args.join))
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
	var out := {online = Net.is_online(), players = Net.players.size(), in_match = _game != null}
	if _game:
		out.time_left = snappedf(_game.time_left, 0.1)
		out.scores = _game.scores
		out.snapshots = _game._snaps.size()
		out.beast_states = _game.beasts.values().map(func(b): return [b.display_name, b.state, snappedf(b.health, 1), b.global_position.snapped(Vector3(0.1, 0.1, 0.1))])
	print("REPORT ", JSON.stringify(out, "", false))
