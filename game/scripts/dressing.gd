class_name Dressing
## High graphics set dressing: Kenney's CC0 props (assets/props/*, licence in each folder) placed around the maps.
## Props inside the play area get a box collider so you can be knocked into them; the "back of the house" sits
## past the farthest the game camera ever gets (z > 21.5), so it shows in the menu's front shots but never blocks play.

static var _scenes := {}


static func prop(parent: Node3D, path: String, pos: Vector3, yaw := 0.0, s := 1.0, solid := false) -> Node3D:
	if not _scenes.has(path):
		_scenes[path] = load("res://assets/props/%s.glb" % path)
	var n: Node3D = _scenes[path].instantiate()
	n.position = pos
	n.rotation_degrees.y = yaw
	n.scale = Vector3.ONE * s
	parent.add_child(n)
	if solid:
		var box := _bounds(n)
		var body := StaticBody3D.new()
		body.transform = n.transform
		var cs := CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		cs.shape.size = box.size
		cs.position = box.get_center()
		body.add_child(cs)
		parent.add_child(body)
	return n


static func _bounds(n: Node3D) -> AABB:
	## The prop's mesh bounds in its own space (before its scale).
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != n:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		out = xf * mi.get_aabb() if first else out.merge(xf * mi.get_aabb())
		first = false
	return out


static func cosmic(a: Arena) -> void:
	## Cosmic Lanes: an arcade corner and a lounge on the brawling floor, ball racks by the lanes,
	## and a back wall of games and a snack bar.
	var hw := a.half_w
	# Arcade corner along the left wall, facing into the room.
	for item in [["arcade-machine", 4.6], ["arcade-machine", 5.9], ["claw-machine", 7.4], ["pinball", 9.0], ["dance-machine", 10.8]]:
		prop(a, "arcade/" + item[0], Vector3(-hw + 0.9, 0, item[1]), 90.0, 2.6, true)
	# Lounge on the right: sofas around a rug and a coffee table, plants and a lamp.
	prop(a, "furniture/rugRound", Vector3(hw - 4.4, 0.01, 9.2), 0.0, 3.0)
	prop(a, "furniture/loungeSofaLong", Vector3(hw - 0.6, 0, 6.4), -90.0, 2.3, true)
	prop(a, "furniture/loungeSofa", Vector3(hw - 3.0, 0, 11.6), 180.0, 2.3, true)
	prop(a, "furniture/tableCoffee", Vector3(hw - 2.9, 0, 8.6), 90.0, 2.3, true)
	prop(a, "nature/pot_large", Vector3(hw - 0.8, 0, 11.4), 0.0, 2.2)
	prop(a, "nature/plant_bushDetailed", Vector3(hw - 0.8, 0.35, 11.4), 0.0, 2.0)
	prop(a, "furniture/lampRoundFloor", Vector3(hw - 0.5, 0, 4.4), 0.0, 2.4)
	prop(a, "arcade/vending-machine", Vector3(hw - 0.75, 0, 2.6), -90.0, 2.6, true)
	# Ball racks with a rainbow of house balls, at the end of each side wall by the lanes.
	for s in [-1.0, 1.0]:
		_ball_rack(a, Vector3(s * (hw - 0.55), 0, 0.9), s)
	# Back of the house (only the menu's front shots see it): a wall of games and a snack bar under a neon sign.
	a._solid(Vector3(hw * 2.0, 6.0, 0.4), Vector3(0, 3.0, 24.6), Look.toy(Color("1b0f3a"), 0.8, false))
	a._solid(Vector3(hw * 2.0, 0.4, 3.0), Vector3(0, -0.2, 23.5), Look.toy(Color("120a2a"), 0.9, false))  # the floor ends at z = 22
	for x in [-7.0, -5.6, -4.2]:
		prop(a, "arcade/arcade-machine", Vector3(x, 0, 23.6), 180.0, 2.6)
	prop(a, "arcade/basketball-game", Vector3(-2.4, 0, 23.2), 180.0, 2.6)
	prop(a, "arcade/air-hockey", Vector3(-3.6, 0, 21.4), 0.0, 2.6)
	prop(a, "arcade/prize-wheel", Vector3(0.0, 0, 24.0), 180.0, 2.6)
	for k in 4:
		prop(a, "furniture/kitchenBar", Vector3(2.0 + k * 1.1, 0, 22.8), 180.0, 2.6)
		prop(a, "furniture/stoolBar", Vector3(2.4 + k * 1.1, 0, 21.6), 0.0, 2.4)
	prop(a, "arcade/vending-machine", Vector3(7.2, 0, 23.8), 180.0, 2.6)
	_neon(a, "SNACKS", Vector3(4.0, 3.6, 24.35), Color("ffe14d"))
	_neon(a, "ARCADE", Vector3(-4.6, 4.2, 24.35), Color("2de2ff"))


static func sunset(a: Arena) -> void:
	## Sunset Lanes: a rooftop bar with stools and parasols, lounge chairs, potted palms, and a skyline of real buildings.
	var hw := a.half_w
	# Bar on the left of the brawling floor, parasols and loungers on the right.
	for k in 3:
		prop(a, "furniture/kitchenBar", Vector3(-hw + 0.75, 0, 5.4 + k * 1.1), 90.0, 2.6, true)
		prop(a, "furniture/stoolBar", Vector3(-hw + 2.0, 0, 5.3 + k * 1.1), -90.0, 2.4, true)
	prop(a, "furniture/kitchenBarEnd", Vector3(-hw + 0.75, 0, 5.4 + 3 * 1.1), 90.0, 2.6, true)
	for z in [6.2, 10.0]:
		prop(a, "city/detail-parasol-a" if z < 8.0 else "city/detail-parasol-b", Vector3(hw - 1.6, 0, z), 0.0, 4.4, true)
		prop(a, "furniture/loungeChairRelax", Vector3(hw - 0.5, 0, z - 1.0), -90.0, 2.4, true)
	for z in [2.4, 11.6]:
		prop(a, "nature/pot_large", Vector3(-hw + 0.8, 0, z), 0.0, 2.2)
		prop(a, "nature/tree_palmDetailedShort", Vector3(-hw + 0.8, 0.3, z), z * 20.0, 1.7)
	# Back of the house: a tiki bar and palms past the camera's reach.
	a._solid(Vector3(hw * 2.0 + 16.0, 0.4, 4.0), Vector3(0, -0.2, 24.0), Look.toy(Color("a8614a"), 0.9, false))  # past the floor's end
	for k in 5:
		prop(a, "furniture/kitchenBar", Vector3(-2.2 + k * 1.1, 0, 23.4), 180.0, 2.6)
	for x in [-6.5, 6.5]:
		prop(a, "city/detail-parasol-a", Vector3(x, 0, 22.5), 0.0, 4.4)
	for x in [-10.5, -3.6, 3.6, 10.5]:
		prop(a, "nature/tree_palmDetailedTall", Vector3(x, 0, 24.5), x * 13.0, 4.8)
	_neon(a, "SUNSET BAR", Vector3(0.0, 3.4, 24.2), Color("ff6f59"))


static func skyline(a: Arena) -> void:
	## Real buildings instead of boxes, mostly below the roof so you look out over the city.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var kinds := ["building-a", "building-b", "building-d", "building-f", "building-g", "building-h", "building-i", "building-j",
		"building-l", "building-m", "building-n"]
	for k in 46:
		var ang := rng.randf_range(-1.9, 1.9)
		var d := rng.randf_range(80.0, 170.0)
		var near_sun := absf(ang + 0.3) < 0.3
		var kind: String = kinds.pick_random() if near_sun or rng.randf() > 0.18 else "building-skyscraper-%s" % ["a", "b", "c", "d", "e"].pick_random()
		var s := rng.randf_range(20.0, 30.0)
		prop(a, "city/" + kind, Vector3(sin(ang) * d, -48.0 + rng.randf_range(-6.0, 6.0), -10.0 - cos(ang) * d), rad_to_deg(-ang) + 180.0, s)
	for k in 10:  # palms ringing the roof edge
		var s := -1.0 if k < 5 else 1.0
		var z := 9.0 - (k % 5) * 8.5
		prop(a, "nature/tree_palmDetailedTall", Vector3(s * (a.half_w + 2.6), 0, z), k * 37.0, rng.randf_range(4.2, 5.2))


static func _ball_rack(a: Arena, at: Vector3, side: float) -> void:
	var metal := Look.toy(Color("8c8ca6"), 0.25, false)
	metal.metallic = 0.7
	a._solid(Vector3(0.7, 1.2, 2.2), at + Vector3(0, 0.6, 0), Look.toy(Color("2a1a55"), 0.5))
	for row in 2:
		Look.mesh(a, Look.box(Vector3(0.75, 0.05, 2.2)), metal, at + Vector3(0, 0.62 + row * 0.5, 0))
		for k in 5:
			var col := Color.from_hsv(fmod(k * 0.19 + row * 0.5, 1.0), 0.75, 0.95)
			var ball := Look.toy(col, 0.08)
			Look.mesh(a, Look.sphere(0.19), ball, at + Vector3(0, 0.86 + row * 0.5, -0.85 + k * 0.42))


static func _neon(a: Arena, text: String, at: Vector3, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = Look.title_font()
	l.font_size = 150
	l.outline_size = 22
	l.modulate = col.lightened(0.3)
	l.outline_modulate = col
	l.pixel_size = 0.008
	l.position = at
	l.rotation.y = PI  # it faces the room, towards the lanes
	a.add_child(l)
	var glow := OmniLight3D.new()
	glow.light_color = col
	glow.light_energy = 1.5
	glow.omni_range = 5.0
	glow.position = at + Vector3(0, 0, -0.8)
	a.add_child(glow)
