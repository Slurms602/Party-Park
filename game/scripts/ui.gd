class_name UI
## Shared UI kit: palette, fonts, theme, buttons, cards and labels.
## The look takes its cues from Super Battle Golf's menus: warm cream paper, deep navy ink, one bold accent,
## heavy italic display type, soft shadows and almost no outlines or glow.
## Two palettes so the UI contrasts with the map behind it: light for bright maps, dark for the blacklight alley.
## The colour names come from the light palette; use() swaps what they hold.

const LIGHT := Color("fff4df")  # fixed: type over the 3D scene, text on coloured pills
const DARK := Color("1d2340")

static var dark := false
static var CREAM := LIGHT  # the paper everything sits on
static var PAPER := Color("fffaf2")  # cards on the paper, hovered buttons
static var SAND := Color("f0dcb6")  # pressed, tracks, dividers
static var NAVY := DARK  # ink
static var RED := Color("e5383b")  # the brand accent
static var MUSTARD := Color("ffb400")
static var TEAL := Color("158f89")
static var SHADOW := Color(0.11, 0.09, 0.2, 0.24)

static var _themes := {}
static var _fonts := {}


static func use(dark_mode: bool) -> void:
	## Pick the palette for what's behind the UI. Controls built afterwards use it.
	dark = dark_mode
	CREAM = Color("1c1538") if dark else LIGHT
	PAPER = Color("2a2152") if dark else Color("fffaf2")
	SAND = Color("3d3274") if dark else Color("f0dcb6")
	NAVY = Color("fff1dc") if dark else DARK
	RED = Color("ff5a64") if dark else Color("e5383b")
	MUSTARD = Color("ffc233") if dark else Color("ffb400")
	TEAL = Color("43d9c6") if dark else Color("158f89")
	SHADOW = Color(0, 0, 0, 0.45) if dark else Color(0.11, 0.09, 0.2, 0.24)


static func ink(c: Color) -> Color:
	## A player or item colour made readable on the current paper.
	return c.lightened(0.3) if dark else c.darkened(0.38)


static func display_font() -> Font:
	## Fraunces Black Italic, soft: big friendly retro-diner type for titles and buttons.
	if not _fonts.has("display"):
		var v := FontVariation.new()
		v.base_font = load("res://assets/fonts/Fraunces-Italic.ttf")
		var ts := TextServerManager.get_primary_interface()
		v.variation_opentype = {ts.name_to_tag("wght"): 900, ts.name_to_tag("SOFT"): 100, ts.name_to_tag("opsz"): 72}
		_fonts.display = v
	return _fonts.display


static func body_font(weight := 700) -> Font:
	## Nunito: rounded and very readable.
	if not _fonts.has(weight):
		var v := FontVariation.new()
		v.base_font = load("res://assets/fonts/Nunito.ttf")
		v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_fonts[weight] = v
	return _fonts[weight]


static func theme() -> Theme:
	if _themes.has(dark):
		return _themes[dark]
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 22
	t.set_color("font_color", "Label", NAVY)
	t.set_constant("outline_size", "Label", 0)
	for type in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", type, pill(CREAM))
		t.set_stylebox("hover", type, pill(PAPER, 7))
		t.set_stylebox("pressed", type, pill(SAND, 1))
		t.set_stylebox("hover_pressed", type, pill(SAND, 1))
		t.set_stylebox("disabled", type, pill(SAND, 0))
		var focus := pill(Color.TRANSPARENT, 0)
		focus.draw_center = false
		focus.border_color = RED
		focus.set_border_width_all(3)
		t.set_stylebox("focus", type, focus)
		t.set_font("font", type, display_font())
		t.set_font_size("font_size", type, 30)
		t.set_color("font_color", type, NAVY)
		t.set_color("font_hover_color", type, RED)
		t.set_color("font_pressed_color", type, RED)
		t.set_color("font_hover_pressed_color", type, RED)
		t.set_color("font_focus_color", type, NAVY)
		t.set_color("font_disabled_color", type, Color(NAVY, 0.35))
		t.set_constant("outline_size", type, 0)
	t.set_icon("arrow", "OptionButton", _icon(func(img: Image): _tri(img, NAVY), 22))
	t.set_constant("arrow_margin", "OptionButton", 18)
	t.set_icon("checked", "CheckButton", _icon(func(img: Image): _toggle(img, true), 56, 32))
	t.set_icon("unchecked", "CheckButton", _icon(func(img: Image): _toggle(img, false), 56, 32))
	t.set_font_size("font_size", "CheckButton", 24)
	var check_bg := pill(Color.TRANSPARENT, 0)
	check_bg.draw_center = false
	for s in ["normal", "hover", "pressed", "hover_pressed"]:
		t.set_stylebox(s, "CheckButton", check_bg)
	var field := card(Color.WHITE, 16, 0)
	field.border_color = SAND
	field.set_border_width_all(3)
	field.content_margin_left = 18
	field.content_margin_right = 18
	var field_focus: StyleBoxFlat = field.duplicate()
	field_focus.border_color = RED
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_font_size("font_size", "LineEdit", 24)
	t.set_color("font_color", "LineEdit", NAVY)
	t.set_color("font_placeholder_color", "LineEdit", Color(NAVY, 0.35))
	t.set_color("caret_color", "LineEdit", RED)
	t.set_color("selection_color", "LineEdit", Color(RED, 0.25))
	t.set_stylebox("panel", "PanelContainer", card(CREAM, 28, 10))
	t.set_stylebox("panel", "PopupMenu", card(PAPER, 18, 8))
	var hover_row := card(Color(RED, 0.12), 12, 0)
	t.set_stylebox("hover", "PopupMenu", hover_row)
	t.set_font("font", "PopupMenu", display_font())
	t.set_font_size("font_size", "PopupMenu", 24)
	t.set_color("font_color", "PopupMenu", NAVY)
	t.set_color("font_hover_color", "PopupMenu", RED)
	t.set_constant("v_separation", "PopupMenu", 10)
	var track := StyleBoxFlat.new()
	track.bg_color = SAND
	track.set_corner_radius_all(8)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var fill: StyleBoxFlat = track.duplicate()
	fill.bg_color = RED
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var knob := _icon(func(img: Image): _dot(img, Color.WHITE, RED), 30)
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", knob)
	var scroll := StyleBoxFlat.new()
	scroll.bg_color = Color(NAVY, 0.25)
	scroll.set_corner_radius_all(4)
	scroll.content_margin_left = 3
	scroll.content_margin_right = 3
	t.set_stylebox("grabber", "VScrollBar", scroll)
	t.set_stylebox("grabber_highlight", "VScrollBar", scroll)
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	_themes[dark] = t
	return t


static func pill(bg: Color, lift := 5, radius := 32) -> StyleBoxFlat:
	## A rounded button shape that sits a few pixels above its soft shadow.
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.set_corner_radius_all(radius)
	b.content_margin_left = 28
	b.content_margin_right = 28
	b.content_margin_top = 6
	b.content_margin_bottom = 10
	b.shadow_color = SHADOW if lift > 0 else Color.TRANSPARENT
	b.shadow_offset = Vector2(0, lift)
	b.shadow_size = 2
	b.anti_aliasing_size = 1.2
	return b


static func card(bg: Color, radius := 24, lift := 6) -> StyleBoxFlat:
	## A panel or card: paper with a soft drop shadow, no border.
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.set_corner_radius_all(radius)
	b.content_margin_left = 24
	b.content_margin_right = 24
	b.content_margin_top = 16
	b.content_margin_bottom = 18
	b.shadow_color = SHADOW if lift > 0 else Color.TRANSPARENT
	b.shadow_offset = Vector2(0, lift)
	b.shadow_size = lift * 2
	return b


static func primary(b: Button) -> Button:
	## The one button that matters on a screen: red with cream type.
	b.add_theme_stylebox_override("normal", pill(RED))
	b.add_theme_stylebox_override("hover", pill(RED.lightened(0.1), 7))
	b.add_theme_stylebox_override("pressed", pill(RED.darkened(0.15), 1))
	b.add_theme_stylebox_override("hover_pressed", pill(RED.darkened(0.15), 1))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, LIGHT)
	return b


static func button(parent: Node, text: String, on_press: Callable, min_w := 320.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 62)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN  # buttons keep their size instead of stretching across a screen
	b.pressed.connect(func():
		sound("ui_back" if text.to_lower() in ["back", "leave", "cancel"] else "ui_click", -4.0)
		on_press.call())
	juicy(b)
	parent.add_child(b)
	return b


static func juicy(c: Control) -> void:
	## Hover/focus: grow a little with a tick; press: squash.
	c.resized.connect(func(): c.pivot_offset = c.size * 0.5)
	var grow := func(on: bool):
		var tw := c.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "scale", Vector2.ONE * (1.04 if on else 1.0), 0.18)
		if on:
			sound("ui_hover", -12.0)
	c.mouse_entered.connect(grow.bind(true))
	c.mouse_exited.connect(grow.bind(false))
	c.focus_entered.connect(grow.bind(true))
	c.focus_exited.connect(grow.bind(false))
	if c is BaseButton:
		c.button_down.connect(func(): c.scale = Vector2.ONE * 0.95)


static func sound(clip: String, volume_db := 0.0) -> void:
	# Looked up at runtime so this class also compiles in headless tests, where autoloads don't exist yet.
	var sfx: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Sfx")
	if sfx:
		sfx.play_ui(clip, volume_db)


static func bar(parent: Node, fill_col: Color, w := 320.0, h := 22.0, track := SAND) -> ProgressBar:
	## A rounded meter: health, XP.
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, h)
	b.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_col
	fill.set_corner_radius_all(int(h / 2.0))
	var bg := StyleBoxFlat.new()
	bg.bg_color = track
	bg.set_corner_radius_all(int(h / 2.0))
	b.add_theme_stylebox_override("fill", fill)
	b.add_theme_stylebox_override("background", bg)
	parent.add_child(b)
	return b


static func label(parent: Node, text: String, size: int, col := NAVY, title := false) -> Label:
	## Flat ink on paper. `title` uses the display face.
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_override("font", display_font() if title else body_font(700 if size < 30 else 800))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


static func hero(parent: Node, text: String, size: int, fill := LIGHT, ink := DARK) -> Label:
	## Big type over the 3D scene: display face with a thick ink outline and a drop shadow.
	var l := label(parent, text, size, fill, true)
	l.add_theme_color_override("font_outline_color", ink)
	l.add_theme_constant_override("outline_size", maxi(size / 5, 6))
	l.add_theme_color_override("font_shadow_color", Color(ink, 0.6))
	l.add_theme_constant_override("shadow_offset_y", maxi(size / 16, 3))
	l.add_theme_constant_override("shadow_outline_size", maxi(size / 5, 6))
	return l


static func panel(parent: Node, title := "") -> VBoxContainer:
	var p := PanelContainer.new()
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	if title != "":
		label(v, title, 48, NAVY, true)
	return v


static func sentence(s: String) -> String:
	## "THROW THE BALL" -> "Throw the ball" (shouty strings from game code, written the calm way).
	return s.substr(0, 1).to_upper() + s.substr(1).to_lower() if s == s.to_upper() else s


static func pop_in(c: Control, delay := 0.0) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2.ONE * 0.85
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, 0.3).set_delay(delay)
	tw.tween_property(c, "modulate:a", 1.0, 0.15).set_delay(delay)


# ------------------------------------------------------------------ generated icons

static func _icon(paint: Callable, w: int, h := -1) -> ImageTexture:
	var img := Image.create(w, w if h < 0 else h, false, Image.FORMAT_RGBA8)
	paint.call(img)
	return ImageTexture.create_from_image(img)


static func _toggle(img: Image, on: bool) -> void:
	## A switch: red track with the knob right when on, sand with the knob left when off.
	var w := img.get_width()
	var h := img.get_height()
	var r := h * 0.5
	for y in h:
		for x in w:
			var cx := clampf(x + 0.5, r, w - r)
			var d := Vector2(x + 0.5 - cx, y + 0.5 - r).length()
			if d < r:
				img.set_pixel(x, y, Color(RED if on else SAND, clampf(r - d, 0.0, 1.0)))
	var kc := Vector2(w - r if on else r, r)
	for y in h:
		for x in w:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(kc)
			if d < r - 3.0:
				img.set_pixel(x, y, Color.WHITE.lerp(img.get_pixel(x, y), clampf(d - (r - 4.0), 0.0, 1.0)))


static func _dot(img: Image, fill: Color, ring: Color) -> void:
	var r := img.get_width() * 0.5
	for y in img.get_height():
		for x in img.get_width():
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			if d < r:
				var c := ring if d > r - 5.0 else fill
				img.set_pixel(x, y, Color(c, clampf(r - d, 0.0, 1.0)))


static func _tri(img: Image, col: Color) -> void:
	var s := img.get_width()
	for y in s:
		for x in s:
			var t := (y - s * 0.3) / (s * 0.4)  # 0 at the top edge, 1 at the tip
			if t >= 0.0 and t <= 1.0 and absf(x + 0.5 - s * 0.5) <= (1.0 - t) * s * 0.4:
				img.set_pixel(x, y, col)
