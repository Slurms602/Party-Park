class_name TouchControls
extends CanvasLayer
## On-screen controls for phones: a thumb stick on the left, action buttons on the right.
## They press the same input actions as the keyboard, so the rest of the game doesn't know the difference.
## GRAB is a toggle here: one thumb can't hold GRAB and wind up PUNCH at the same time.

const RADIUS := 110.0
const BUTTONS := [  # label, action, offset from bottom-right, radius, color
	["PUNCH", "punch", Vector2(-180, -180), 92.0, Color("ff3fb4")],
	["GRAB", "grab", Vector2(-370, -110), 72.0, Color("2de2ff")],
	["JUMP", "jump", Vector2(-150, -390), 64.0, Color("3ddc97")],
	["DIVE", "dive", Vector2(-350, -300), 60.0, Color("ffe14d")],
]

var _stick := -1  # touch index driving the stick
var _origin := Vector2.ZERO
var _vec := Vector2.ZERO
var _pad: Node2D
var _buttons: Array[TouchScreenButton] = []
var me_id := 1  # the local player's peer id (set by Game)
var _grab_on := false
var _grab_t := 0.0
var _was_holding := false


func _ready() -> void:
	layer = 5
	_pad = Node2D.new()
	_pad.draw.connect(_draw_pad)
	add_child(_pad)
	for b in BUTTONS:
		_buttons.append(_button(b[0], b[1], b[3], b[4]))
	var grab := _buttons[1]
	grab.action = ""  # handled as a toggle below
	grab.pressed.connect(func(): _set_grab(not _grab_on))
	var pause := _button("II", "pause", 40.0, Color(1, 1, 1, 0.7))
	pause.set_meta("top", true)
	_buttons.append(pause)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _button(text: String, action: String, r: float, col: Color) -> TouchScreenButton:
	var img := Image.create(int(r * 2), int(r * 2), false, Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var d := Vector2(x - r, y - r).length()
			if d < r:
				img.set_pixel(x, y, Color(col, 0.38) if d < r - 6.0 else Color(col, 0.95))
	var b := TouchScreenButton.new()
	b.texture_normal = ImageTexture.create_from_image(img)
	b.action = action
	var shape := CircleShape2D.new()
	shape.radius = r
	b.shape = shape
	b.shape_centered = true
	b.set_meta("r", r)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Look.title_font())
	l.add_theme_font_size_override("font_size", int(r * 0.42))
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.12))
	l.size = Vector2(r * 2, r * 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(l)
	add_child(b)
	return b


func _layout() -> void:
	var size := get_viewport().get_visible_rect().size
	for i in BUTTONS.size():
		var r: float = BUTTONS[i][3]
		_buttons[i].position = size + BUTTONS[i][2] - Vector2(r, r)
	_buttons[-1].position = Vector2(size.x * 0.5 + 110.0, 22.0)  # pause, next to the clock


func _set_grab(on: bool) -> void:
	_grab_on = on
	_grab_t = 0.0
	_was_holding = false
	if on:
		Input.action_press("grab")
	else:
		Input.action_release("grab")
	_buttons[1].modulate = Color(1.6, 1.6, 1.6) if on else Color.WHITE


func _process(dt: float) -> void:
	if not _grab_on:
		return
	var me: Beast = null
	for b: Beast in get_tree().get_nodes_in_group("beasts"):
		if b.pid == me_id:
			me = b
	var holding := me != null and (me.holding != null or me.net_holding)
	_grab_t += dt
	# Let go once whatever we held is gone (bowled, thrown, knocked loose), or if we grabbed nothing.
	if (_was_holding and not holding) or (not holding and _grab_t > 2.0) or (me and me.state >= Beast.BALL):
		_set_grab(false)
	_was_holding = _was_holding or holding


func _input(e: InputEvent) -> void:
	var half := get_viewport().get_visible_rect().size.x * 0.45
	if e is InputEventScreenTouch:
		if e.pressed and _stick < 0 and e.position.x < half and e.position.y > 140.0:
			_stick = e.index
			_origin = e.position
			_steer(Vector2.ZERO)
		elif not e.pressed and e.index == _stick:
			_stick = -1
			_steer(Vector2.ZERO)
	elif e is InputEventScreenDrag and e.index == _stick:
		_steer((e.position - _origin).limit_length(RADIUS) / RADIUS)


func _steer(v: Vector2) -> void:
	_vec = v
	for pair in [["left", -v.x], ["right", v.x], ["up", -v.y], ["down", v.y]]:
		if pair[1] > 0.15:
			Input.action_press(pair[0], pair[1])
		else:
			Input.action_release(pair[0])
	_pad.queue_redraw()


func _draw_pad() -> void:
	var size := get_viewport().get_visible_rect().size
	var c := _origin if _stick >= 0 else Vector2(230, size.y - 330)  # resting spot hints where to put your thumb
	_pad.draw_circle(c, RADIUS, Color(1, 1, 1, 0.12))
	_pad.draw_arc(c, RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.5), 4.0)
	_pad.draw_circle(c + _vec * RADIUS, 46.0, Color(1, 1, 1, 0.55))


func _exit_tree() -> void:
	_steer(Vector2.ZERO)
	Input.action_release("grab")
