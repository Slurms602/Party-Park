class_name Hud
extends CanvasLayer
## Match HUD: clock, live scoreboard, kill feed, STRIKE! callouts, your health and charge, pause menu, results.

var board: Scoreboard
var paused := false
var _clock: Label
var _feed: VBoxContainer
var _big: Label
var _sub: Label
var _health: ProgressBar
var _charge: ProgressBar
var _hint: Label
var _pause: PanelContainer
var _results: PanelContainer
var _flash: ColorRect


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	root.add_child(_flash)

	_clock = _label(root, 54, Color("2de2ff"))
	_clock.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_clock.offset_top = 12

	board = Scoreboard.new()
	board.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	board.offset_left = -480
	board.offset_right = -16
	board.offset_top = 16
	board.offset_bottom = 300
	root.add_child(board)

	_feed = VBoxContainer.new()
	_feed.position = Vector2(20, 20)
	root.add_child(_feed)

	_big = _label(root, 120, Color.WHITE)
	_big.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_big.offset_top = -200
	_sub = _label(root, 36, Color.WHITE)
	_sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_sub.offset_top = -90

	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.offset_top = -120
	bottom.offset_left = -220
	bottom.offset_right = 220
	bottom.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(bottom)
	_hint = _label(bottom, 26, Color("ffe14d"))
	_charge = _bar(bottom, Color("ffe14d"), 14)
	_health = _bar(bottom, Color("3ddc97"), 22)
	var keys := _label(bottom, 16, Color(1, 1, 1, 0.6))
	keys.text = "WASD move · LMB punch (hold = haymaker / bowl) · RMB hold = grab · Space jump · Shift dive · Esc menu"

	_pause = _panel(root)
	var pv := _pause.get_child(0)
	_label(pv, 48, Color.WHITE).text = "Paused"
	_button(pv, "Resume", func(): _toggle_pause())
	_button(pv, "Leave match", func(): Net.leave())

	_results = _panel(root)
	_results.custom_minimum_size = Vector2(900, 520)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause") and not _results.visible:
		_toggle_pause()


func _toggle_pause() -> void:
	paused = not paused
	_pause.visible = paused


func set_time(t: float) -> void:
	_clock.text = "%d:%02d" % [int(ceil(t)) / 60, int(ceil(t)) % 60]
	_clock.modulate = Color.RED if t < 10.0 and fmod(t, 1.0) > 0.5 else Color.WHITE


func set_me(health: float, charge: float, balled: bool, carrying: bool) -> void:
	_health.value = health
	_charge.visible = charge >= 0.0
	_charge.value = maxf(charge, 0.0) * 100.0
	_hint.text = "MASH BUTTONS TO WAKE UP!" if balled else \
		"Hold LMB, then release to BOWL!" if carrying else ""


func impact() -> void:
	_flash.color = Color(1, 0.95, 0.8, 0.35)
	_flash.create_tween().tween_property(_flash, "color:a", 0.0, 0.12)


func feed(text: String, col: Color) -> void:
	var l := _label(_feed, 22, col.lightened(0.3))
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if _feed.get_child_count() > 6:
		_feed.get_child(0).queue_free()
	var tw := l.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func big(text: String, col: Color, sub := "") -> void:
	_big.text = text
	_big.modulate = col
	_sub.text = sub
	_big.pivot_offset = _big.size * 0.5
	var tw := _big.create_tween()
	_big.scale = Vector2(0.3, 0.3)
	_big.self_modulate.a = 1.0
	_sub.self_modulate.a = 1.0
	tw.tween_property(_big, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.4)
	tw.tween_property(_big, "self_modulate:a", 0.0, 0.4)
	tw.parallel().tween_property(_sub, "self_modulate:a", 0.0, 0.4)


func results(rows: Array) -> void:
	_results.visible = true
	_pause.visible = false
	var v := _results.get_child(0)
	var winner: Dictionary = rows[0] if not rows.is_empty() else {name = "Nobody", color = Color.WHITE}
	var title := _label(v, 72, winner.color)
	title.text = "%s WINS!" % winner.name
	var sb := Scoreboard.new()
	sb.big = true
	sb.custom_minimum_size = Vector2(860, 340)
	sb.set_rows(rows, 0.0)
	v.add_child(sb)
	_label(v, 22, Color(1, 1, 1, 0.7)).text = "Back to the lobby in a few seconds..."


func _label(parent: Node, size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", maxi(size / 6, 4))
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.12))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _bar(parent: Node, col: Color, h: int) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(440, h)
	b.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(h / 2)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(h / 2)
	b.add_theme_stylebox_override("fill", fill)
	b.add_theme_stylebox_override("background", bg)
	parent.add_child(b)
	return b


func _panel(parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.03, 0.16, 0.92)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(28)
	sb.border_color = Color("ff3fb4")
	sb.set_border_width_all(3)
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	p.visible = false
	parent.add_child(p)
	return p


func _button(parent: Node, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 56)
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b
