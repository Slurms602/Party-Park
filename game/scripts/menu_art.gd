class_name MenuArt
## The menu's signature art, drawn in code: the cream paper backdrop with its striped curved edge, and the logo.


class Backdrop extends Control:
	## Cream paper over the left of the screen with a curved, striped right edge (Super Battle Golf's swoosh).
	## `edge` is how far right the paper reaches at mid-height; it glides when the screen changes.
	var edge := 560.0
	var slant := 1.0  # 1 = the main menu's strong sweep, 0 = a calmer edge for busy screens

	func glide(to: float, to_slant: float) -> void:
		var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "edge", to, 0.45)
		tw.tween_property(self, "slant", to_slant, 0.45)
		tw.tween_method(func(_v): queue_redraw(), 0.0, 1.0, 0.45)

	func edge_at(y: float) -> float:
		## x of the paper's edge at height y (a quadratic curve from top to bottom).
		var t := clampf(y / maxf(size.y, 1.0), 0.0, 1.0)
		var top := edge + 150.0 * slant + 40.0
		var mid := edge + 40.0 * slant
		var bottom := edge - 170.0 * slant - 20.0
		return (1.0 - t) * (1.0 - t) * top + 2.0 * (1.0 - t) * t * mid + t * t * bottom

	func _draw() -> void:
		for band in [[46.0, UI.MUSTARD], [30.0, UI.RED], [0.0, UI.CREAM]]:
			var pts := PackedVector2Array([Vector2(0, 0)])
			for i in 33:
				var y := size.y * i / 32.0
				pts.append(Vector2(edge_at(y) + band[0], y))
			pts.append(Vector2(0, size.y))
			draw_colored_polygon(pts, band[1])


class Logo extends Control:
	## "Bowling your Friends" as a chunky sticker: the "o" is a bowling ball trailing a comet swoosh.
	func _init() -> void:
		custom_minimum_size = Vector2(640, 250)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f := UI.display_font()
		var fs := 148
		var base := Vector2(18, 150)
		_swoosh(base)
		var w_b := f.get_string_size("B", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_sticker(f, base, "B", fs, UI.LIGHT)
		var r := fs * 0.27
		var ball := base + Vector2(w_b + r * 1.32 + 10.0, -r * 1.0)  # sits where the "o" would, outline and all
		_ball(ball, r)
		_sticker(f, base + Vector2(w_b + r * 2.64 + 14.0, 0), "wling", fs, UI.LIGHT)
		# "your Friends" on a second line, red with a cream inner outline.
		var fs2 := 80
		var p2 := base + Vector2(96, 86)
		draw_string_outline(f, p2 + Vector2(0, 7), "your Friends", HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, 30, UI.DARK)
		draw_string_outline(f, p2, "your Friends", HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, 30, UI.DARK)
		draw_string_outline(f, p2, "your Friends", HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, 12, UI.LIGHT)
		draw_string(f, p2, "your Friends", HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, UI.RED)

	func _sticker(f: Font, pos: Vector2, text: String, fs: int, fill: Color) -> void:
		var o := int(fs * 0.17)
		draw_string_outline(f, pos + Vector2(0, fs * 0.07), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, o, UI.DARK)  # depth
		draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, o, UI.DARK)
		draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fill)
		draw_string(f, pos + Vector2(0, -fs * 0.02), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.35))  # top light

	func _ball(c: Vector2, r: float) -> void:
		draw_circle(c + Vector2(0, r * 0.18), r + r * 0.32, UI.DARK)  # depth
		draw_circle(c, r + r * 0.32, UI.DARK)
		draw_circle(c, r, UI.RED)
		draw_circle(c + Vector2(r * 0.12, r * 0.12), r * 0.86, UI.RED.darkened(0.18))  # shading
		draw_arc(c, r * 0.72, deg_to_rad(200), deg_to_rad(260), 16, Color(1, 1, 1, 0.75), r * 0.14)  # gloss
		for h in [Vector2(-0.22, -0.28), Vector2(0.12, -0.36), Vector2(0.08, 0.02)]:
			draw_circle(c + h * r * 1.6, r * 0.13, UI.DARK)

	func _swoosh(base: Vector2) -> void:
		## A comet tail sweeping up behind the word, red with a mustard core.
		for layer in [[1.0, UI.DARK, 10.0], [1.0, UI.RED, 0.0], [0.55, UI.MUSTARD, 0.0]]:
			var pts := PackedVector2Array()
			var back := PackedVector2Array()
			for i in 25:
				var t := i / 24.0
				var p := base + Vector2(lerpf(-10.0, 640.0, t), lerpf(40.0, -150.0, t * t))
				var thick: float = (sin(t * PI) * 38.0 + t * 30.0) * layer[0] + layer[2]
				var n := Vector2(-(-300.0 * t), 650.0).normalized()  # normal of the curve, pointing down-right
				pts.append(p - n * thick * 0.5)
				back.append(p + n * thick * 0.5)
			back.reverse()
			pts.append_array(back)
			draw_colored_polygon(pts, layer[1])
