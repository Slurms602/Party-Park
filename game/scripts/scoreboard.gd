class_name Scoreboard
extends Control
## Bowling-alley scoreboard: one row per player with their recent rolls (X, /, -, 7) and a running total.
## big = the overhead alley screen; otherwise a compact HUD panel.

var big := false
var rows: Array = []  # [{name, color, total, rolls: Array[String]}], already sorted
var time_left := 0.0
var _flash := ""
var _flash_color := Color.WHITE
var _flash_t := 0.0


func set_rows(r: Array, t: float) -> void:
	rows = r
	time_left = t
	queue_redraw()


func flash(text: String, col: Color) -> void:
	_flash = text
	_flash_color = col
	_flash_t = 2.2


func _process(dt: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= dt
		queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var w := size.x
	var h := size.y
	var frames := 10 if big else 5
	var head := h * 0.17 if big else 0.0
	var row_h := minf((h - head) / maxf(rows.size(), 4.0), 92.0) if big else 30.0
	var fs := int(row_h * 0.5)
	if big:
		draw_rect(Rect2(Vector2.ZERO, size), Color("0a0820"))
		draw_rect(Rect2(0, 0, w, head), Color("1d0f4a"))
		_text(font, Vector2(24, head * 0.68), "BOWLING YOUR FRIENDS", int(head * 0.45), Color("ffe14d"))
		var clock := "%d:%02d" % [int(time_left) / 60, int(time_left) % 60]
		_text(font, Vector2(w - 24, head * 0.68), clock, int(head * 0.5), Color("2de2ff"), HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		draw_rect(Rect2(0, 0, w, row_h * maxf(rows.size(), 1.0) + 8.0), Color(0.04, 0.02, 0.12, 0.72))
	var name_w := w * (0.24 if big else 0.36)
	var total_w := w * (0.14 if big else 0.2)
	var box_w := (w - name_w - total_w - 16.0) / frames
	for i in rows.size():
		var r: Dictionary = rows[i]
		var y := head + 4.0 + i * row_h
		var stripe := Color(1, 1, 1, 0.04 if i % 2 == 0 else 0.0)
		draw_rect(Rect2(4, y, w - 8, row_h - 4), stripe)
		draw_rect(Rect2(8, y + 4, 8, row_h - 12), r.color)
		_text(font, Vector2(24, y + row_h * 0.68), r.name, fs, r.color.lightened(0.35))
		var rolls: Array = r.rolls.slice(maxi(r.rolls.size() - frames, 0))
		for f in frames:
			var bx := name_w + f * box_w
			var rect := Rect2(bx + 2, y + 3, box_w - 4, row_h - 10)
			draw_rect(rect, Color(1, 1, 1, 0.08))
			draw_rect(rect, Color(1, 1, 1, 0.25), false, 1.5)
			if f < rolls.size():
				var code: String = rolls[f]
				var col := Color.WHITE
				match code:
					"X": col = Color("ffe14d")
					"/": col = Color("2de2ff")
					"-": col = Color(1, 1, 1, 0.4)
				_text(font, Vector2(bx + box_w * 0.5, y + row_h * 0.68), code, fs, col, HORIZONTAL_ALIGNMENT_CENTER)
		_text(font, Vector2(w - 16, y + row_h * 0.7), str(r.total), int(fs * 1.25), Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)

	if big and _flash_t > 0.0:  # the alley-screen STRIKE! animation
		var t := 2.2 - _flash_t
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
		var s := 1.0 + 0.25 * sin(t * 12.0) * exp(-t * 2.0) + minf(t, 0.15) * 2.0 - 0.3
		draw_set_transform(size * 0.5, sin(t * 7.0) * 0.05, Vector2(s, s))
		var c := _flash_color.lerp(Color.WHITE, 0.5 + 0.5 * sin(t * 20.0))
		_text(font, Vector2(0, h * 0.12), _flash, int(h * 0.35), c, HORIZONTAL_ALIGNMENT_CENTER)
		draw_set_transform(Vector2.ZERO)


func _text(font: Font, pos: Vector2, s: String, fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var width := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= width * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= width
	draw_string_outline(font, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(fs / 8, 2), Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
