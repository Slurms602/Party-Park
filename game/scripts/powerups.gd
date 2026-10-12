class_name Powerups
extends Node3D
## Item boxes on the back floor (Super Battle Golf's ItemSpawner + weighted ItemPool) and thrown bowling balls.
## The host spawns boxes, hands out items and simulates the balls; clients draw both from snapshots.
## Boxes sit where you bowl from, so the fight stays away from the pins.

signal picked(b: Beast, kind: String)
signal ball_hit(by: int, victim: Beast)

const RESPAWN := 8.0
const BALL_R := 0.3
const KINDS := {
	gloves = {name = "BIG GLOVES", hint = "punches hit harder", color = Color("ff3fb4"), weight = 3.0, time = 10.0},
	shoes = {name = "TURBO SHOES", hint = "run faster", color = Color("2de2ff"), weight = 3.0, time = 10.0},
	sticky = {name = "STICKY GRIP", hint = "whoever you carry can't wake up", color = Color("3ddc97"), weight = 2.0, time = 25.0},
	golden = {name = "GOLDEN BALL", hint = "your next bowl scores double", color = Color("ffcc33"), weight = 2.0, time = 25.0},
	bumpers = {name = "BUMPERS", hint = "no gutter on your next bowl", color = Color("ff8c2a"), weight = 2.0, time = 25.0},
	giant_pin = {name = "GIANT PIN", hint = "every swing is a smash", color = Color("fbf7ee"), weight = 2.0, time = 20.0, uses = 3},
	ball = {name = "BOWLING BALL", hint = "punch to throw it", color = Color("b980ff"), weight = 3.0, time = 20.0},
}

var is_behind := func(_pid: int) -> bool: return false  # set by Game: trailing players get better items
var _server := false
var _spots: Array[Vector3] = []
var _boxes: Array[Node3D] = []
var _timers: Array[float] = []
var _balls := {}  # id -> {body, by, t, hit}  (host) or id -> visual Node3D (clients)
var _next_id := 1
var _pins: Array = []
static var _ball_mesh: SphereMesh
static var _ball_mat: StandardMaterial3D


func setup(arena: Arena, is_server: bool) -> void:
	_server = is_server
	_pins = arena.pins
	_spots.assign(arena.item_spots())
	_timers = [3.0, 5.0, 7.0]  # the first boxes pop in just after BOWL!
	for s in _spots:
		_boxes.append(_box(s))


func _box(at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = at
	root.visible = false
	add_child(root)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.55
	ring.outer_radius = 0.68
	Look.mesh(root, ring, Look.neon(Color("b980ff"), 2.0), Vector3(0, 0.03, 0)).scale = Vector3(1, 0.25, 1)
	var cube := Node3D.new()
	cube.name = "Cube"
	cube.position.y = 0.9
	root.add_child(cube)
	Look.mesh(cube, Look.box(Vector3.ONE * 0.62), Look.toy(Color("8a3dff"), 0.15))
	for axis in [Vector3(0.66, 0.14, 0.66), Vector3(0.14, 0.66, 0.66)]:  # gold ribbon, like a present
		Look.mesh(cube, Look.box(axis), Look.neon(Color("ffcc33"), 0.8))
	var q := Label3D.new()
	q.text = "?"
	q.font = Look.title_font()
	q.font_size = 120
	q.outline_size = 24
	q.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	q.pixel_size = 0.006
	q.modulate = Color.WHITE
	q.outline_modulate = Color("1a0d3d")
	q.position = Vector3(0, 0.65, 0)
	cube.add_child(q)
	root.add_to_group("item_boxes")
	return root


func _process(dt: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for i in _boxes.size():  # spin and bob (Super Battle Golf's ItemBoxRotationPerSecond)
		var cube: Node3D = _boxes[i].get_node("Cube")
		cube.rotation.y = t * 1.6 + i
		cube.position.y = 0.9 + sin(t * 2.5 + i) * 0.1


# ---------------------------------------------------------------- host

func server_update(dt: float, beasts: Array) -> void:
	for i in _boxes.size():
		if not _boxes[i].visible:
			_timers[i] -= dt
			if _timers[i] <= 0.0:
				_boxes[i].visible = true
			continue
		for b: Beast in beasts:
			var d := Vector2(b.global_position.x - _spots[i].x, b.global_position.z - _spots[i].z).length()
			if d < 0.95 and b.global_position.y < 2.5 and b.state <= Beast.DIVE and b.item == "":
				_boxes[i].visible = false
				_timers[i] = RESPAWN
				give(b, roll(b.pid))
				break
	for id in _balls.keys():
		var p: Dictionary = _balls[id]
		var rb: RigidBody3D = p.body
		p.t += dt
		if p.t > 4.0 or rb.global_position.y < -3.0 or (p.t > 1.0 and rb.linear_velocity.length() < 1.0):
			rb.queue_free()
			_balls.erase(id)


func roll(pid: int) -> String:
	## Weighted random item. Players who are well behind are twice as likely to get the scoring helpers.
	var behind: bool = is_behind.call(pid)
	var total := 0.0
	var weights := {}
	for k in KINDS:
		weights[k] = KINDS[k].weight * (2.0 if behind and k in ["golden", "bumpers", "ball"] else 1.0)
		total += weights[k]
	var r := randf() * total
	for k in weights:
		r -= weights[k]
		if r <= 0.0:
			return k
	return "gloves"


func give(b: Beast, kind: String) -> void:
	b.item = kind
	b.item_t = KINDS[kind].time
	b.item_uses = KINDS[kind].get("uses", 0)
	picked.emit(b, kind)


func spawn_ball(by: Beast, pos: Vector3, vel: Vector3) -> void:
	var rb := RigidBody3D.new()
	rb.mass = 2.0
	rb.continuous_cd = true
	rb.contact_monitor = true
	rb.max_contacts_reported = 4
	rb.physics_material_override = PhysicsMaterial.new()
	rb.physics_material_override.bounce = 0.3
	var cs := CollisionShape3D.new()
	cs.shape = SphereShape3D.new()
	cs.shape.radius = BALL_R
	rb.add_child(cs)
	rb.add_child(ball_visual())
	add_child(rb)
	rb.global_position = pos
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3.UP.cross(vel) / BALL_R
	rb.add_collision_exception_with(by)
	for pin in _pins:  # it's a weapon, not a free roll: it passes through the pins
		rb.add_collision_exception_with(pin)
	var p := {body = rb, by = by.pid, t = 0.0, hit = []}
	rb.body_entered.connect(_on_ball_hit.bind(p))
	_balls[_next_id] = p
	_next_id += 1


func _on_ball_hit(other: Node, p: Dictionary) -> void:
	var rb: RigidBody3D = p.body
	if not other is Beast or p.hit.has(other) or not is_instance_valid(rb):
		return
	var b: Beast = other
	var rel := (rb.linear_velocity - b.linear_velocity).length()
	if rel < 4.0:
		return
	p.hit.append(b)
	var k := clampf((rel - 4.0) / 12.0, 0.0, 1.0)
	var dir := (rb.linear_velocity * Vector3(1, 0, 1)).normalized()
	b.take_hit(p.by, dir, lerpf(30.0, 55.0, k), lerpf(8.0, 15.0, k), 0.5, lerpf(0.6, 1.3, k), "CLONK!" if k > 0.5 else "")
	ball_hit.emit(p.by, b)
	b.fx.emit("smack", (rb.global_position + b.global_position) * 0.5, 2.0)


# ---------------------------------------------------------------- sync

func pack() -> Array:
	var mask := 0
	for i in _boxes.size():
		mask |= int(_boxes[i].visible) << i
	var balls := []
	for id in _balls:
		balls.append([id, _balls[id].body.global_position])
	return [mask, balls]


func apply(a: Array, b: Array, w: float) -> void:
	## Clients: show boxes and move thrown balls between two snapshots.
	for i in _boxes.size():
		_boxes[i].visible = b[0] & (1 << i) != 0
	var prev := {}
	for e in a[1]:
		prev[e[0]] = e[1]
	var seen := {}
	for e in b[1]:
		seen[e[0]] = true
		if not _balls.has(e[0]):
			_balls[e[0]] = ball_visual()
			add_child(_balls[e[0]])
		_balls[e[0]].global_position = prev.get(e[0], e[1]).lerp(e[1], w)
	for id in _balls.keys():
		if not seen.has(id):
			_balls[id].queue_free()
			_balls.erase(id)


static func ball_visual() -> Node3D:
	## A glossy purple bowling ball with three finger holes.
	if _ball_mesh == null:
		_ball_mesh = Look.sphere(BALL_R)
		_ball_mat = Look.toy(Color("6a2bd9"), 0.05)
		_ball_mat.metallic = 0.3
	var root := Node3D.new()
	Look.mesh(root, _ball_mesh, _ball_mat)
	var hole := Look.sphere(0.045)
	var dark := Look.toy(Color("10061f"), 0.8, false)
	for o in [Vector3(-0.06, 0.27, -0.1), Vector3(0.06, 0.27, -0.1), Vector3(0.0, 0.24, 0.12)]:
		Look.mesh(root, hole, dark, o)
	return root
