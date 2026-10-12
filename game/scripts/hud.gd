class_name Hud
extends CanvasLayer
## Match HUD. Pieces taken from Super Battle Golf's UI, in the cream-and-ink style of the menus:
## tee-off style countdown, match-end countdown with urgency pops, kill-feed chips, callouts,
## a power bar over your bowler, button prompts, a player card, and a results screen with the winner dancing.

var board: Scoreboard
var paused := false
var _root: Control
var _clock: Label
var _clock_pill: PanelContainer
var _feed: VBoxContainer
var _big: Label
var _sub: Label
var _burst: Burst
var _count: Label
var _banner: Label
var _me_name: Label
var _health: ProgressBar
var _status: Label
var _prompts: HBoxContainer
var _prompt_key := ""
var _charge: ChargeMeter
var _boxes: BoxMarks
var _pause: PanelContainer
var _results: Control
var _flash: ColorRect
var _confetti: CPUParticles2D
var _last_clock := -1
var _card_style: StyleBoxFlat
var _stats: Label


class Burst extends Control:
	## Rotating starburst behind big callouts.
	var color := Color.WHITE
	var t := 0.0
	func _process(dt: float) -> void:
		t += dt
		queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		for i in 16:
			var a := t * 0.6 + TAU * i / 16.0
			draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a - 0.08) * r, c + Vector2.from_angle(a + 0.08) * r]),
				Color(color, 0.22 if i % 2 == 0 else 0.1))


class ChargeMeter extends Control:
	## Power bar that floats over your bowler while you wind up (Super Battle Golf's SwingPowerBarUi).
	var fill := 0.0
	func _draw() -> void:
		var full := fill >= 0.999
		var wob := sin(Time.get_ticks_msec() * 0.03) * 3.0 if full else 0.0
		var r := Rect2(Vector2(-70, -12 + wob), Vector2(140, 24))
		draw_style_box(UI.pill(UI.NAVY, 3, 12), r)
		var inner := Rect2(r.position + Vector2(5, 5), Vector2((r.size.x - 10) * fill, r.size.y - 10))
		var fill_style := UI.pill(UI.MUSTARD.lerp(UI.RED, fill) if not full else UI.CREAM.lerp(UI.MUSTARD, 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.04)), 0, 8)
		draw_style_box(fill_style, inner)
		if full:
			var f := UI.display_font()
			draw_string_outline(f, Vector2(-30, -20 + wob), "Max!", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 10, UI.DARK)
			draw_string(f, Vector2(-30, -20 + wob), "Max!", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UI.MUSTARD)


class BoxMarks extends Control:
	## "?" chips on the bottom edge pointing at item boxes behind the camera.
	var pts: Array = []
	func _draw() -> void:
		var bob := absf(sin(Time.get_ticks_msec() * 0.006)) * 6.0
		for p: Vector2 in pts:
			var c := p - Vector2(0, bob)
			draw_circle(c + Vector2(0, 3), 26.0, Color(UI.NAVY, 0.3))
			draw_circle(c, 26.0, UI.CREAM)
			draw_circle(c, 21.0, UI.RED)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-10, 25), c + Vector2(10, 25), c + Vector2(0, 38)]), UI.CREAM)
			var f := UI.display_font()
			draw_string(f, c + Vector2(-8, 11), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, UI.CREAM)


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UI.theme()
	add_child(_root)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	_root.add_child(_flash)

	_clock_pill = PanelContainer.new()
	_clock_pill.add_theme_stylebox_override("panel", UI.card(UI.CREAM, 34, 5))
	_clock_pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_clock_pill.offset_top = 14
	_clock_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.add_child(_clock_pill)
	_clock = UI.label(_clock_pill, "3:00", 52, UI.NAVY, true)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.custom_minimum_size.x = 150

	board = Scoreboard.new()
	board.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	board.offset_left = -470
	board.offset_right = -16
	board.offset_top = 16
	board.offset_bottom = 340
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(board)

	_feed = VBoxContainer.new()
	_feed.position = Vector2(18, 18)
	_feed.add_theme_constant_override("separation", 6)
	_root.add_child(_feed)

	_burst = Burst.new()
	_burst.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_burst.offset_left = -360
	_burst.offset_right = 360
	_burst.offset_top = -460
	_burst.offset_bottom = 60
	_burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_burst.modulate.a = 0.0
	_root.add_child(_burst)
	_big = _center_label(150, -300)
	_sub = _center_label(40, -150)
	_count = _center_label(200, -170)
	_banner = _center_label(64, -330)

	var card := PanelContainer.new()
	_card_style = UI.card(UI.CREAM, 22, 5)
	_card_style.border_width_left = 12
	card.add_theme_stylebox_override("panel", _card_style)
	card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	card.offset_left = 18
	card.offset_top = -112
	card.offset_bottom = -18
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 4)
	card.add_child(cv)
	_me_name = UI.label(cv, "", 28, UI.NAVY, true)
	_health = UI.bar(cv, UI.TEAL)
	_status = UI.label(cv, "", 17, Color(UI.NAVY, 0.7))

	_prompts = HBoxContainer.new()
	_prompts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompts.offset_top = -74
	_prompts.offset_bottom = -24
	_prompts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompts.add_theme_constant_override("separation", 22)
	_root.add_child(_prompts)

	_charge = ChargeMeter.new()
	_charge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charge.visible = false
	_root.add_child(_charge)
	_stats = UI.hero(_root, "", 18)  # under the clock: phones have their buttons in the bottom corners
	_stats.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_stats.offset_top = 108
	_stats.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boxes = BoxMarks.new()
	_boxes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_boxes)

	_pause = _overlay_panel("Paused")
	var pv := _pause.get_child(0)
	UI.primary(UI.button(pv, "Resume", func(): _toggle_pause()))
	for pair in [["Music", "music"], ["Sound effects", "sfx"]]:
		UI.label(pv, pair[0], 18, Color(UI.NAVY, 0.65))
		var s := HSlider.new()
		s.max_value = 1.0
		s.step = 0.05
		s.value = Prefs.get(pair[1])
		s.custom_minimum_size = Vector2(320, 30)
		s.value_changed.connect(func(x):
			Prefs.set(pair[1], x)
			Prefs.apply())
		pv.add_child(s)
	UI.button(pv, "Leave match", func():
		Prefs.save()
		Net.leave())

	_confetti = CPUParticles2D.new()
	_confetti.emitting = false
	_confetti.one_shot = true
	_confetti.amount = 160
	_confetti.lifetime = 2.6
	_confetti.explosiveness = 0.9
	_confetti.direction = Vector2(0, 1)
	_confetti.spread = 60.0
	_confetti.initial_velocity_min = 200.0
	_confetti.initial_velocity_max = 600.0
	_confetti.gravity = Vector2(0, 500)
	_confetti.angular_velocity_min = -400.0
	_confetti.angular_velocity_max = 400.0
	_confetti.scale_amount_min = 6.0
	_confetti.scale_amount_max = 12.0
	_confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_confetti.emission_rect_extents = Vector2(700, 10)
	var ramp := Gradient.new()
	for i in 5:
		ramp.add_point(i / 4.0, [UI.RED, UI.MUSTARD, UI.TEAL, UI.CREAM, Color("ff8fb1")][i])
	_confetti.color_initial_ramp = ramp
	_root.add_child(_confetti)


func _center_label(size: int, y: float) -> Label:
	var l := UI.hero(_root, "", size)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	l.offset_left = -800
	l.offset_right = 800
	l.offset_top = y
	l.offset_bottom = y + size * 1.3
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.modulate.a = 0.0
	return l


func _overlay_panel(title: String) -> PanelContainer:
	var v := UI.panel(_root, title)
	var p: PanelContainer = v.get_parent()
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.visible = false
	return p


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause") and (_results == null):
		_toggle_pause()


func _toggle_pause() -> void:
	paused = not paused
	_pause.visible = paused
	Sfx.play_ui("ui_click" if paused else "ui_back", -4.0)
	if paused:
		UI.pop_in(_pause)


# ------------------------------------------------------------------ live info

func set_time(t: float) -> void:
	var secs := int(ceil(t))
	_clock.text = "%d:%02d" % [secs / 60, secs % 60]
	if secs != _last_clock and secs <= 10 and secs > 0:  # urgency pop each second (Super Battle Golf's MatchEndCountdown)
		_clock_pill.pivot_offset = _clock_pill.size * 0.5
		_clock_pill.scale = Vector2.ONE * 1.25
		_clock_pill.create_tween().tween_property(_clock_pill, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK)
		countdown(str(secs), Color("ff3b4e"), 120)
		Sfx.play_ui("tick", -2.0)
	_last_clock = secs
	_clock.add_theme_color_override("font_color", UI.RED if secs <= 30 else UI.NAVY)


func set_me(player_name: String, col: Color, health: float, balled: bool, ko_left: float) -> void:
	_me_name.text = player_name
	_card_style.border_color = col
	_health.visible = health >= 0.0  # -1: this minigame has no health (nobody gets knocked out)
	_health.value = health
	var fill: StyleBoxFlat = _health.get_theme_stylebox("fill")
	fill.bg_color = UI.RED if health < 25 else (UI.MUSTARD if health < 55 else UI.TEAL)
	_status.text = "Knocked out  ·  %.1fs" % ko_left if balled else ("Woozy!" if health >= 0.0 and health < 25 else "Ready to brawl")
	_status.add_theme_color_override("font_color", Color(UI.NAVY, 0.7))


func set_stats(text: String) -> void:
	_stats.text = text


func set_box_marks(pts: Array) -> void:
	_boxes.pts = pts
	_boxes.queue_redraw()


func set_item(text: String, col: Color) -> void:
	## The item you're holding replaces the status line under your health bar.
	_status.text = text
	_status.add_theme_color_override("font_color", UI.ink(col))


func set_prompts(items: Array) -> void:
	## items: [[key, action], ...] shown as key caps at the bottom centre (Super Battle Golf's ButtonPrompt).
	var key := str(items)
	if key == _prompt_key:
		return
	_prompt_key = key
	for c in _prompts.get_children():
		c.queue_free()
	for it in items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var cap := PanelContainer.new()
		var warn: bool = it.size() > 2
		var style := UI.pill(UI.RED if warn else UI.NAVY, 4, 12)
		style.content_margin_left = 14
		style.content_margin_right = 14
		cap.add_theme_stylebox_override("panel", style)
		UI.label(cap, it[0], 20, UI.CREAM, true)  # inverse of the keycap's ink
		row.add_child(cap)
		UI.hero(row, UI.sentence(it[1]), 28)
		_prompts.add_child(row)
		UI.pop_in.call_deferred(row)


func set_charge(screen_pos: Vector2, fill: float) -> void:
	_charge.visible = fill >= 0.0
	if _charge.visible:
		_charge.position = screen_pos
		_charge.fill = fill
		_charge.queue_redraw()


# ------------------------------------------------------------------ events

func feed(text: String, col: Color) -> void:
	feed_event(text, col, "", UI.NAVY)


func feed_event(a: String, a_col: Color, verb: String, verb_col: Color, b := "", b_col := UI.NAVY) -> void:
	## A kill-feed chip: [name] [VERB] [name] (Super Battle Golf's InfoFeedMessage layout), names inked in their colour.
	var chip := PanelContainer.new()
	var style := UI.card(UI.CREAM, 18, 4)
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	style.content_margin_left = 16
	style.content_margin_right = 16
	chip.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	chip.add_child(row)
	UI.label(row, a, 22, UI.ink(a_col), true)
	if verb != "":
		var pill := PanelContainer.new()
		var ps := UI.pill(verb_col, 0, 12)
		ps.content_margin_left = 12
		ps.content_margin_right = 12
		ps.content_margin_top = 2
		ps.content_margin_bottom = 4
		pill.add_theme_stylebox_override("panel", ps)
		UI.label(pill, UI.sentence(verb), 17, UI.LIGHT, true)
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pill)
	if b != "":
		UI.label(row, b, 22, UI.ink(b_col), true)
	_feed.add_child(chip)
	UI.pop_in.call_deferred(chip)
	if _feed.get_child_count() > 6:
		_feed.get_child(0).queue_free()
	var tw := chip.create_tween()
	tw.tween_interval(4.5)
	tw.tween_property(chip, "modulate:a", 0.0, 0.5)
	tw.tween_callback(chip.queue_free)


func callout(text: String, col: Color, sub := "", confetti := false) -> void:
	_big.text = UI.sentence(text)
	_big.add_theme_color_override("font_color", col)
	_sub.text = sub
	_burst.color = col
	for c in [_big, _sub, _burst]:
		c.pivot_offset = c.size * 0.5
		c.modulate.a = 1.0
	_big.scale = Vector2.ONE * 0.2
	_big.rotation = -0.25
	var tw := _big.create_tween().set_parallel()
	tw.tween_property(_big, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_big, "rotation", -0.04, 0.4).set_trans(Tween.TRANS_BACK)
	for c in [_big, _sub, _burst]:
		tw.tween_property(c, "modulate:a", 0.0, 0.4).set_delay(1.7)
	if confetti:
		_confetti.position = Vector2(_root.size.x * 0.5, -20)
		_confetti.restart()


func countdown(text: String, col: Color, size := 200) -> void:
	_count.text = text
	_count.add_theme_font_size_override("font_size", size)
	_count.add_theme_color_override("font_color", col)
	_count.pivot_offset = _count.size * 0.5
	_count.modulate.a = 1.0
	_count.scale = Vector2.ONE * 1.8
	var tw := _count.create_tween()
	tw.tween_property(_count, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_count, "modulate:a", 0.0, 0.45).set_delay(0.3)


func banner(text: String, col: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", col)
	_banner.pivot_offset = _banner.size * 0.5
	_banner.modulate.a = 1.0
	var tw := _banner.create_tween()
	for i in 3:
		tw.tween_property(_banner, "scale", Vector2.ONE * 1.12, 0.2)
		tw.tween_property(_banner, "scale", Vector2.ONE, 0.2)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.5).set_delay(0.6)


func impact() -> void:
	_flash.color = Color(1, 0.95, 0.8, 0.35)
	_flash.create_tween().tween_property(_flash, "color:a", 0.0, 0.12)


# ------------------------------------------------------------------ results

func results(rows: Array, winner_color: Color, winner_skin: Dictionary, stats: Array, prog := {}) -> void:
	## stats: the minigame's extra columns, [heading, row key] (Arena.stats).
	_pause.visible = false
	_results = Control.new()
	_results.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_results)
	var dim := ColorRect.new()
	dim.color = Color(UI.NAVY, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_results.add_child(dim)
	dim.create_tween().tween_property(dim, "color:a", 0.6, 0.6)

	# The winner dances on a spotlit turntable.
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	svc.offset_right = 760
	_results.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 20, 0)
	key.light_energy = 1.5
	vp.add_child(key)
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8a70ff")
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.fov = 38.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0.5, 4.2), Vector3(0, 0.2, 0))
	var model := BowlerModel.new()
	vp.add_child(model)
	model.build(winner_color, winner_skin)
	_results.set_meta("model", model)

	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	card.offset_left = -860
	card.offset_top = -380
	_results.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	var winner: Dictionary = rows[0] if not rows.is_empty() else {name = "Nobody", color = UI.NAVY}
	UI.label(v, "Winner!", 46, UI.RED, true)
	UI.label(v, winner.name, 88, UI.NAVY, true)
	var table := GridContainer.new()
	table.columns = 3 + stats.size()
	table.add_theme_constant_override("h_separation", 28)
	table.add_theme_constant_override("v_separation", 4)
	v.add_child(table)
	for head in ["#", "Player", "Pts"] + stats.map(func(c): return c[0]):
		UI.label(table, head, 18, Color(UI.NAVY, 0.55), true)
	for i in rows.size():
		var r: Dictionary = rows[i]
		var cells := [str(i + 1), r.name, str(r.total)] + stats.map(func(c): return str(r.get(c[1], 0)))
		for c in cells.size():
			UI.label(table, cells[c], 28, UI.ink(r.color) if c == 1 else UI.NAVY, true)
	if not prog.is_empty():
		_progress_panel(v, prog)
	UI.label(v, "Back to the lobby in a few seconds...", 17, Color(UI.NAVY, 0.55))
	UI.pop_in.call_deferred(card)
	_confetti.position = Vector2(_root.size.x * 0.5, -20)
	_confetti.restart()


func _progress_panel(parent: Control, prog: Dictionary) -> void:
	## Your XP for the match filling the level bar, then any achievements and unlocks.
	var a: Dictionary = prog.before
	var b: Dictionary = prog.after
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	UI.label(row, "+%d XP" % prog.xp, 30, UI.RED, true)
	var lvl := UI.label(row, "Level %d" % a.level, 30, UI.NAVY, true)
	var bar := UI.bar(row, UI.RED, 300, 20)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.value = 100.0 * a.into / a.need
	var tw := bar.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.6)
	if b.level > a.level:
		tw.tween_property(bar, "value", 100.0, 0.6)
		tw.tween_callback(func():
			lvl.text = "Level %d" % b.level
			lvl.add_theme_color_override("font_color", UI.RED)
			UI.pop_in(lvl)
			Sfx.play_ui("spare")
			bar.value = 0.0)
	tw.tween_property(bar, "value", 100.0 * b.into / b.need, 0.6)
	var lines: Array = prog.achievements.map(func(id): return ["Achievement  ·  " + Progress.ACHIEVEMENTS[id].name, UI.TEAL])
	lines += prog.unlocks.map(func(r): return ["Unlocked  ·  " + Progress.reward_name(r), UI.RED])
	for i in mini(lines.size(), 4):
		UI.label(parent, lines[i][0] if i < 3 or lines.size() == 4 else "...and %d more: check Customize" % (lines.size() - 3), 22, lines[i][1], true)


func _process(dt: float) -> void:
	if _results and _results.has_meta("model"):
		var m: BowlerModel = _results.get_meta("model")
		m.rotation.y = PI + sin(Time.get_ticks_msec() * 0.0009) * 0.7
		m.pose(dt, {dance = true})
