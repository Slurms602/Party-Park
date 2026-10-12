class_name Arena
extends Node3D
## A minigame's field and its special rules. Every minigame lives in res://minigames/<id>/ (its own git repo) and extends this.
## The match (Game) runs everything shared: bowlers, fists, grabbing and throwing, items, networking, scores and the HUD.
## An arena builds its world in setup() and overrides the hooks below where its game differs; the defaults suit a plain brawl.

var game  # the match (Game), set before setup; null in tests and behind the menu. Untyped: Game refers to Arena.
var half_w := 10.0  # the camera stays this close to the middle
var cam_look := Vector3(0, -6.5, -14.0)  # game camera direction
var cam_focus := Vector3.ZERO  # what the camera watches when you're out
var go_word := "Go!"  # the end of the 3, 2, 1 countdown
var throw_word := "THROW"  # the touch PUNCH button while carrying someone
var show_frames := false  # the HUD scoreboard shows bowling frames
var screen_board: Control  # an in-world scoreboard (Scoreboard) the match keeps up to date, if the field has one
var pins: Array[RigidBody3D] = []  # props a thrown bowling ball flies through instead of knocking over
var _server := false

static var _maps := {}


static func maps() -> Dictionary:
	## Every playable map: id -> {name, map, rules, seconds, arena, dark?, menu?}, gathered from each res://minigames/*/minigame.gd.
	if _maps.is_empty():
		var dirs := Array(DirAccess.get_directories_at("res://minigames"))
		dirs.sort()
		for dir in dirs:
			var path := "res://minigames/%s/minigame.gd" % dir
			if ResourceLoader.exists(path):
				_maps.merge(load(path).MAPS)
	return _maps


static func make(map_id: String) -> Arena:
	return maps().get(map_id, maps().values()[0]).arena.new()


static func is_dark(map_id: String) -> bool:
	return maps().get(map_id, {}).get("dark", false)  # the UI goes dark to match a dark map


# ---------------------------------------------------------------- hooks

func setup(is_server: bool) -> void:
	_server = is_server


func spawn_point(i: int) -> Vector3:
	var a := TAU * (i % 8) / 8.0 + PI * 0.5
	return Vector3(cos(a) * 4.8, 1.2, sin(a) * 4.8)


func safe_radius() -> float:
	## How far from the middle a bot can wander before it's in danger (only fields with an edge to fall off).
	return INF


func item_spots() -> Array:
	## Where item boxes appear. None by default: no items.
	return []


func server_update(_dt: float, _beasts: Array) -> void:
	## Host, every physics tick: the minigame's rules. Score with game.scores + game.push_scores(), finish with game.end_match().
	pass


func snapshot() -> PackedByteArray:
	## Host: extra state clients need to draw (sent with every snapshot, so keep it small). Empty sends nothing.
	return PackedByteArray()


func apply_snapshot(_a: PackedByteArray, _b: PackedByteArray, _w: float) -> void:
	## Clients: draw the blend of two snapshot() results.
	pass


func in_pit(_pos: Vector3) -> bool:
	## A spot a ball can't get out of: the bowler pops back out at ball_return_point().
	return false


func ball_return_point(_x: float) -> Vector3:
	return spawn_point(0)


func aim(_by: Beast, f: Vector3) -> Vector3:
	## The direction a carried player gets thrown, given where the thrower faces (aim assist goes here).
	return f


func launched(_by: Beast, _ball: Beast) -> void:
	## Host: a carried player was just thrown.
	pass


func follow(_ball: Beast) -> bool:
	## Whether the camera follows a ball you just threw for a moment.
	return false


func carry_prompts(_me: Beast) -> Array:
	## Button prompts while you carry someone.
	return [["HOLD LMB", "WIND UP"], ["RELEASE", "THROW!"]]


func bot_carry(_b: Beast, m: Dictionary, inp: Dictionary, dt: float) -> Dictionary:
	## A bot carrying someone (grab is already held): wind up and throw them where it's facing.
	m.wind = m.get("wind", -1.0) + dt if m.get("wind", -1.0) >= 0.0 else 0.0
	inp.punch = m.wind < 0.6
	if not inp.punch:
		m.wind = -1.0
	return inp


func bot_home(t: float) -> Vector3:
	## Where an idle bot mills about.
	return Vector3(sin(t * 0.4), 0.0, cos(t * 0.3)) * 2.0


func bot_chases(_b: Beast, _o: Beast) -> bool:
	## Whether a bot picks a fight with o.
	return true


# ---------------------------------------------------------------- building

func _body(shape: Shape3D, pos: Vector3, friction := 0.8, group := "") -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = pos
	var cs := CollisionShape3D.new()
	cs.shape = shape
	sb.add_child(cs)
	sb.physics_material_override = PhysicsMaterial.new()
	sb.physics_material_override.friction = friction
	if group != "":
		sb.add_to_group(group)
	add_child(sb)
	return sb


func _solid(size: Vector3, pos: Vector3, mat: Material, friction := 0.8, group := "") -> StaticBody3D:
	var bs := BoxShape3D.new()
	bs.size = size
	var sb := _body(bs, pos, friction, group)
	Look.mesh(sb, Look.box(size), mat)
	return sb


# ---------------------------------------------------------------- the pin: bowling's, but also hats, the giant pin item and the board

static var _pin_mat: StandardMaterial3D
static var _pin_cache: ArrayMesh


static func pin_material() -> StandardMaterial3D:
	if _pin_mat == null:
		_pin_mat = Look.toy(Color.WHITE, 0.15)
		_pin_mat.vertex_color_use_as_albedo = true
		_pin_mat.emission_enabled = true  # pins glow a little under the blacklight
		_pin_mat.emission = Color("fff6ea")
		_pin_mat.emission_energy_multiplier = 0.35
	return _pin_mat


static func pin_mesh() -> ArrayMesh:
	# A lathe-turned pin: (height, radius) profile revolved, with two red neck stripes.
	if _pin_cache:
		return _pin_cache
	var prof := [[0.0, 0.0], [0.0, 0.09], [0.06, 0.13], [0.18, 0.175], [0.34, 0.19], [0.48, 0.175],
		[0.62, 0.135], [0.74, 0.09], [0.82, 0.075], [0.9, 0.08], [0.98, 0.095], [1.06, 0.1],
		[1.13, 0.085], [1.18, 0.05], [1.2, 0.0]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 20
	for r in prof.size() - 1:
		for s in seg:
			var quad := []
			for c in [[r, s], [r + 1, s], [r + 1, s + 1], [r, s + 1]]:
				var a: float = TAU * c[1] / seg
				quad.append(Vector3(cos(a) * prof[c[0]][1], prof[c[0]][0], sin(a) * prof[c[0]][1]))
			var y: float = (quad[0].y + quad[1].y) * 0.5
			st.set_color(Color("e8202a") if (y > 0.7 and y < 0.76) or (y > 0.79 and y < 0.84) else Color("fbf7ee"))
			for v in [quad[0], quad[2], quad[1], quad[0], quad[3], quad[2]]:
				st.add_vertex(v)
	st.generate_normals()
	_pin_cache = st.commit()
	return _pin_cache
