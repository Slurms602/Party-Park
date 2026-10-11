class_name UI
## Shared UI kit: theme, chunky bouncy buttons with sounds, panels and labels.
## Inspired by Super Battle Golf's menus (animated buttons, per-element UI sounds), in our own neon style.

const PINK := Color("ff3fb4")
const YELLOW := Color("ffe14d")
const CYAN := Color("2de2ff")
const NIGHT := Color("1a0d3d")
const INK := Color("0b0618")

static var _theme: Theme


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = Look.font(true)
	t.default_font_size = 22
	var normal := box(Color("2a1460"), PINK)
	var hover := box(PINK, YELLOW)
	var pressed := box(Color("c01f86"), YELLOW, 2)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(3)
	focus.border_color = YELLOW
	focus.set_corner_radius_all(18)
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("focus", type, focus)
		t.set_stylebox("disabled", type, box(Color("2a1a40"), Color("4a3a60")))
		t.set_font("font", type, Look.title_font())
		t.set_font_size("font_size", type, 28)
		t.set_color("font_outline_color", type, INK)
		t.set_constant("outline_size", type, 6)
	var field := box(Color("120a2a"), CYAN, 0)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", box(Color("1a0f3a"), YELLOW, 0))
	t.set_font_size("font_size", "LineEdit", 24)
	t.set_stylebox("panel", "PanelContainer", box(Color(NIGHT, 0.93), PINK, 8, 26))
	t.set_stylebox("panel", "PopupMenu", box(NIGHT, PINK, 0))
	t.set_font_size("font_size", "PopupMenu", 22)
	t.set_color("font_outline_color", "Label", INK)
	t.set_constant("outline_size", "Label", 6)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("120a2a")
	track.set_corner_radius_all(8)
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	var fill := track.duplicate()
	fill.bg_color = PINK
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	_theme = t
	return t


static func box(bg: Color, border: Color, shadow := 6, radius := 18) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(3)
	b.set_corner_radius_all(radius)
	b.content_margin_left = 18
	b.content_margin_right = 18
	b.content_margin_top = 10
	b.content_margin_bottom = 10
	b.shadow_color = Color(0, 0, 0, 0.45)
	b.shadow_offset = Vector2(0, shadow)
	return b


static func button(parent: Node, text: String, on_press: Callable, min_w := 320.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 60)
	b.pressed.connect(func():
		sound("ui_back" if text in ["BACK", "LEAVE", "CANCEL"] else "ui_click", -4.0)
		on_press.call())
	juicy(b)
	parent.add_child(b)
	return b


static func juicy(c: Control) -> void:
	## Hover/focus: grow and tilt with a tick; press: squash.
	c.resized.connect(func(): c.pivot_offset = c.size * 0.5)
	var grow := func(on: bool):
		var tw := c.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "scale", Vector2.ONE * (1.06 if on else 1.0), 0.18)
		tw.tween_property(c, "rotation", randf_range(-0.025, 0.025) if on else 0.0, 0.18)
		if on:
			sound("ui_hover", -12.0)
	c.mouse_entered.connect(grow.bind(true))
	c.mouse_exited.connect(grow.bind(false))
	c.focus_entered.connect(grow.bind(true))
	c.focus_exited.connect(grow.bind(false))
	if c is BaseButton:
		c.button_down.connect(func(): c.scale = Vector2.ONE * 0.94)


static func sound(clip: String, volume_db := 0.0) -> void:
	# Looked up at runtime so this class also compiles in headless tests, where autoloads don't exist yet.
	var sfx: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Sfx")
	if sfx:
		sfx.play_ui(clip, volume_db)


static func label(parent: Node, text: String, size: int, col: Color, title := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", maxi(size / 6, 4))
	if title:
		l.add_theme_font_override("font", Look.title_font())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


static func panel(parent: Node, title := "") -> VBoxContainer:
	var p := PanelContainer.new()
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	if title != "":
		label(v, title, 40, YELLOW, true)
	return v


static func pop_in(c: Control, delay := 0.0) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2.ONE * 0.7
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, 0.3).set_delay(delay)
	tw.tween_property(c, "modulate:a", 1.0, 0.15).set_delay(delay)
