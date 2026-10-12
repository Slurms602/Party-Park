class_name Scoreboard
extends Control
## Bowling-alley scoreboard: one row per player with rank, recent rolls (X / F - 7) and a running total.
## big = the overhead alley screen (a dark LED board in the 3D scene); otherwise the compact cream HUD card.

const MARK_COLORS := {"X": Color("ffe14d"), "/": Color("2de2ff"), "-": Color(1, 1, 1, 0.4), "F": Color("ff3b4e")}
const INK_MARKS := {"X": UI.RED, "/": UI.TEAL, "-": Color(UI.NAVY, 0.35), "F": Color("a3171f")}

var big := false
var rows: Array = []  # [{name, color, total, rolls: Array[String], me}], sorted best first
var time_left := 0.0
var _flash := ""
var _flash_color := Color.WHITE
var _flash_t := 0.0
var _pulse := {}  # name -> seconds left of the "just scored" glow
var _last_totals := {}


func set_rows(r: Array, t: float) -> void:
	for row in r:
		if _last_totals.has(row.name) and row.total > _last_totals[row.name]:
			_pulse[row.name] = 0.8
		_last_totals[row.name] = row.total
	rows = r
	time_left = t
	queue_redraw()


func flash(text: String, col: Color) -> void:
	_flash = text
	_flash_color = col
	_flash_t = 2.2


func _process(dt: float) -> void:
	if _flash_t > 0.0 or not _pulse.is_empty():
		_flash_t -= dt
		for k in _pulse.keys():
			_pulse[k] -= dt
			if _pulse[k] <= 0.0:
				_pulse.erase(k)
		queue_redraw()


func _draw() -> void:
	var title := Look.title_font() if big else UI.display_font()
	var body := Look.font(true) if big else UI.body_font(800)
	var ink := Color.WHITE if big else UI.NAVY
	var w := size.x
	var h := size.y
	var frames := 10 if big else 4
	var head := h * 0.17 if big else 34.0
	var row_h := minf((h - head) / maxf(rows.size(), 4.0), 92.0) if big else 34.0
	var fs := int(row_h * 0.52)
	if big:
		draw_rect(Rect2(Vector2.ZERO, size), Color("0a0820"))
		draw_rect(Rect2(0, 0, w, head), Color("1d0f4a"))
		_text(title, Vector2(24, head * 0.7), "BOWLING YOUR FRIENDS", int(head * 0.48), Color("ffe14d"))
		var clock := "%d:%02d" % [int(time_left) / 60, int(time_left) % 60]
		_text(title, Vector2(w - 24, head * 0.7), clock, int(head * 0.55), Color("2de2ff"), HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		draw_style_box(UI.card(UI.CREAM, 20, 5), Rect2(0, 0, w, head + row_h * maxf(rows.size(), 1.0) + 10.0))
		_text(title, Vector2(18, 28), "Scores", 24, UI.NAVY)
	var rank_w := 34.0 if not big else 56.0
	var name_w := w * (0.22 if big else 0.36)
	var total_w := w * (0.13 if big else 0.17)
	var box_w := (w - rank_w - name_w - total_w - 20.0) / frames
	for i in rows.size():
		var r: Dictionary = rows[i]
		var y := head + 4.0 + i * row_h
		var glow: float = _pulse.get(r.name, 0.0)
		var bg := Color(1, 1, 1, 0.05 if i % 2 == 0 else 0.0) if big else Color(UI.SAND, 0.4 if i % 2 == 0 else 0.0)
		if r.get("me", false):
			bg = Color(r.color, 0.22)
		if glow > 0.0:
			bg = bg.lerp(Color(1, 0.9, 0.3, 0.45), glow)
		draw_rect(Rect2(6, y, w - 12, row_h - 4), bg)
		var rank_col: Color = ([Color("ffe14d"), Color("d8e2ff"), Color("ff9a4d")][i] if i < 3 else Color(1, 1, 1, 0.5)) if big \
			else ([UI.RED, UI.NAVY, Color("b8601f")][i] if i < 3 else Color(UI.NAVY, 0.45))
		_text(title, Vector2(10 + rank_w * 0.5, y + row_h * 0.7), str(i + 1), fs, rank_col, HORIZONTAL_ALIGNMENT_CENTER)
		if i == 0 and r.total > 0:
			_crown(Vector2(10 + rank_w * 0.5, y + row_h * 0.12), row_h * 0.22)
		draw_rect(Rect2(rank_w + 10, y + 5, 6, row_h - 14), r.color)
		_text(body, Vector2(rank_w + 24, y + row_h * 0.68), r.name, fs, r.color.lightened(0.35) if big else r.color.darkened(0.4))
		var rolls: Array = r.rolls.slice(maxi(r.rolls.size() - frames, 0))
		for f in frames:
			var bx := rank_w + name_w + f * box_w
			var rect := Rect2(bx + 2, y + 4, box_w - 4, row_h - 12)
			if big:
				draw_rect(rect, Color(1, 1, 1, 0.07))
				draw_rect(rect, Color(1, 1, 1, 0.22), false, 1.5)
			else:
				draw_style_box(UI.pill(Color(UI.SAND, 0.75), 0, 6), rect)
			if f < rolls.size():
				var code: String = rolls[f]
				_text(title, Vector2(bx + box_w * 0.5, y + row_h * 0.68), code, fs, (MARK_COLORS if big else INK_MARKS).get(code, ink), HORIZONTAL_ALIGNMENT_CENTER)
		_text(title, Vector2(w - 16, y + row_h * 0.72), str(r.total), int(fs * (1.25 + glow * 0.4)), ink, HORIZONTAL_ALIGNMENT_RIGHT)

	if big and _flash_t > 0.0:  # the alley-screen STRIKE! animation
		var t := 2.2 - _flash_t
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
		var s := 1.0 + 0.25 * sin(t * 12.0) * exp(-t * 2.0) + minf(t, 0.15) * 2.0 - 0.3
		draw_set_transform(size * 0.5, sin(t * 7.0) * 0.05, Vector2(s, s))
		var c := _flash_color.lerp(Color.WHITE, 0.5 + 0.5 * sin(t * 20.0))
		_text(title, Vector2(0, h * 0.12), _flash, int(h * 0.36), c, HORIZONTAL_ALIGNMENT_CENTER)
		draw_set_transform(Vector2.ZERO)


func _crown(c: Vector2, s: float) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(-s, s * 0.6), c + Vector2(-s, -s * 0.3), c + Vector2(-s * 0.5, s * 0.1),
		c + Vector2(0, -s * 0.6), c + Vector2(s * 0.5, s * 0.1), c + Vector2(s, -s * 0.3), c + Vector2(s, s * 0.6)]), Color("ffcc33"))


func _text(font: Font, pos: Vector2, s: String, fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var width := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= width * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= width
	if big:  # LED board: dark outline; the cream HUD card is flat ink
		draw_string_outline(font, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(fs / 6, 3), Color(0.03, 0.01, 0.08, 0.9))
	draw_string(font, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
