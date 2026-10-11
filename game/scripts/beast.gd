class_name Beast
extends RigidBody3D
## A wobbly jelly bowler. The host runs sim() every physics tick. Clients get a frozen copy
## that game.gd moves to match snapshots, and _process() animates the limbs from the same state on both sides.

signal knocked_out(victim: Beast, by: int)
signal flattened(by: int, victim: Beast)  # a bowled ball ran someone over
signal fx(clip: String, pos: Vector3, volume_db: float)
signal hurt(victim: Beast, by: int, dir: Vector3, power: float, label: String)  # drives hit reactions on every peer

enum { STAND, DIVE, BALL, CARRIED }

const BODY_R := 0.42
const BODY_H := 1.5
const BALL_R := 0.55
const SPEED := 5.6
const MAX_HEALTH := 100.0
const KO_TIME := 7.5
const MIN_KO := 3.0  # mashing can't wake you before this, so there's always a window to bowl you
const IMMUNE_TIME := 2.0  # Gang Beasts kInvincibleTime
const PUNCH_TIME := 0.24
const FULL_CHARGE := 0.9

var pid := 0
var display_name := ""
var color := Color.WHITE
var arena: Arena

# Replicated state (the host writes it; snapshots copy it to clients)
var state := STAND
var facing := 0.0
var health := MAX_HEALTH
var charge := 0.0
var charging := false
var punch_t := [0.0, 0.0]
var holding: Node3D = null
var reaching := false
var net_holding := false  # clients only know *that* we hold something
var immune := 0.0
var leader := false

# Host-only
var held_by: Beast = null
var last_toucher := 0
var projectile_t := 0.0
var ko_time := 0.0
var ball_t := 0.0
var since_hit := 9.0
var stagger := 0.0
var dive_t := 0.0
var landed_t := 0.0
var cooldown := {punch = 0.0, dive = 0.0, jump = 0.0, grab = 0.0, pins_sfx = 0.0}
var down_t := 0.0  # knocked down: limp, no control (heavy hits, throws, tackles)
var last_hit_by := 0  # credit for body slams while you're flying
var ko_by := 0  # who balled us (bots go for their own knockouts first)
var combo := 0
var _combo_target: Beast = null
var _combo_t := 9.0
var _atk := {}  # the punch in progress: {t, heavy, power, club, hit}
var _jab_buffer := 0.0
var hold_time := 0.0
var bot_mem := {}
var _punch_hand := 0
var _prev := {}
var _dive_hits := []
var _grounded := false
var _on_oil := false

var _col: CollisionShape3D
var _capsule := CapsuleShape3D.new()
var _sphere := SphereShape3D.new()
var _mat_stand := PhysicsMaterial.new()
var _mat_ball := PhysicsMaterial.new()
var _mat_dive := PhysicsMaterial.new()

# Visuals
var _vis: Node3D
var _body: MeshInstance3D
var _body_mat: StandardMaterial3D
var _pupils: Array[MeshInstance3D] = []
var _fists: Array[MeshInstance3D] = []
var _feet: Array[MeshInstance3D] = []
var _overlay: Node3D
var _stars: Array[MeshInstance3D] = []
var _bubble: MeshInstance3D
var _crown: Node3D
var _label: Label3D
var _phase := 0.0
var _last_pos := Vector3.ZERO
var _speed := 0.0
var _flash := 0.0
var _last_health := MAX_HEALTH
var _bar: MeshInstance3D
var _hit_shake := 0.0
var _lean := 0.0  # jelly whiplash: a damped spring tilting the body away from the last hit
var _lean_v := 0.0
var _lean_axis := Vector3.RIGHT
var _squash := Vector3.ONE

const BAR_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled;
instance uniform float fill = 1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	bool edge = UV.x < 0.025 || UV.x > 0.975 || UV.y < 0.18 || UV.y > 0.82;
	vec3 col = mix(vec3(1.0, 0.2, 0.25), vec3(0.25, 0.9, 0.45), smoothstep(0.2, 0.6, fill));
	ALBEDO = edge ? vec3(0.03, 0.01, 0.06) : (UV.x < fill ? col : vec3(0.12, 0.06, 0.18));
	ALPHA = 0.92;
}
"""
static var _bar_mat: ShaderMaterial


func setup(id: int, info: Dictionary, a: Arena, simulate: bool) -> void:
	pid = id
	display_name = info.name
	color = info.color
	arena = a
	mass = 1.5
	linear_damp = 0.1
	continuous_cd = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = not simulate
	contact_monitor = simulate
	max_contacts_reported = 6
	_capsule.radius = BODY_R
	_capsule.height = BODY_H
	_sphere.radius = BALL_R
	_mat_stand.friction = 0.0  # we steer with forces; ground friction would only trip us over
	_mat_ball.friction = 0.6
	_mat_ball.bounce = 0.25
	_mat_dive.friction = 0.35
	_col = CollisionShape3D.new()
	add_child(_col)
	_set_ball_shape(false)
	add_to_group("beasts")
	if simulate:
		body_entered.connect(_on_body_entered)
	_build_visuals()


# ================================================================= host simulation

func sim(inp: Dictionary, dt: float) -> void:
	for k in cooldown:
		cooldown[k] -= dt
	for h in 2:
		punch_t[h] = maxf(punch_t[h] - dt, 0.0)
	immune = maxf(immune - dt, 0.0)
	projectile_t = maxf(projectile_t - dt, 0.0)
	since_hit += dt
	_ground_check()
	match state:
		STAND: _sim_stand(inp, dt)
		DIVE: _sim_dive(dt)
		BALL, CARRIED: _sim_ball(inp, dt)
	_prev = inp
	if global_position.z < -Arena.LANE_LEN and global_position.y < Arena.PIT_Y + 1.0 and state != CARRIED:
		_respawn(arena.ball_return_point(global_position.x), Vector3(0, 3.0, 3.5))  # out of the pit via the ball return
	elif global_position.y < -12.0 or absf(global_position.x) > 30.0 or absf(global_position.z) > 40.0:
		_respawn(arena.spawn_point(randi() % 8))


func _pressed(inp: Dictionary, k: String) -> bool:
	return inp.get(k, false) and not _prev.get(k, false)


func _sim_stand(inp: Dictionary, dt: float) -> void:
	if since_hit > 3.0:
		health = minf(health + 6.0 * dt, MAX_HEALTH)
	stagger = maxf(stagger - dt, 0.0)
	_combo_t += dt
	if down_t > 0.0:  # flopped over: no balance and no control until we get back up
		down_t -= dt
		reaching = false
		charging = false
		_atk.clear()
		release_hold()
		if down_t <= 0.0:
			physics_material_override = _mat_stand
		return
	var move: Vector2 = inp.get("move", Vector2.ZERO).limit_length(1.0)
	if move.length() > 0.15:
		facing = atan2(-move.x, -move.y)
	var speed := SPEED * (0.5 if charging else 1.0) * (0.9 if holding is Beast else 1.0)
	var hv := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var traction := (0.22 if _on_oil else 1.0) if _grounded else 0.3
	apply_central_force(((Vector3(move.x, 0.0, move.y) * speed - hv) * 10.0 * traction).limit_length(60.0) * mass)
	_balance((0.12 if stagger > 0.0 else 1.0) * (0.55 if health < 25.0 else 1.0))  # nearly out = visibly woozy

	if _pressed(inp, "jump") and _grounded and cooldown.jump <= 0.0:
		linear_velocity.y = 0.0
		apply_central_impulse(Vector3.UP * 5.2 * mass)
		cooldown.jump = 0.3
	if _pressed(inp, "dive") and cooldown.dive <= 0.0 and not holding is Beast:
		_start_dive()
		return

	# Grab: hold to keep hold of whatever is in front of you (Gang Beasts style).
	reaching = inp.get("grab", false) and holding == null
	if inp.get("grab", false) and holding == null and cooldown.grab <= 0.0:
		_try_grab()  # hold to grab whatever you touch
	if holding != null:
		if not inp.get("grab", false) or not is_instance_valid(holding):
			release_hold()
		else:
			_update_hold(dt)

	# Punch: tap for a jab, hold to charge a haymaker (or a bowl, if you're carrying a ball).
	if _pressed(inp, "punch"):
		charging = true
		charge = 0.0
	if charging:
		charge = minf(charge + dt, FULL_CHARGE)
		if not inp.get("punch", false):
			charging = false
			var power := clampf(charge / FULL_CHARGE, 0.0, 1.0)
			if holding is Beast and holding.state == CARRIED:
				_bowl(power)
			elif holding is Beast:
				_throw_held(power)
			elif charge < 0.2:
				_jab_buffer = 0.18  # fires as soon as the previous punch recovers
			else:
				_start_attack(true, clampf((charge - 0.2) / (FULL_CHARGE - 0.2), 0.0, 1.0))
			charge = 0.0
	_jab_buffer -= dt
	if _jab_buffer > 0.0 and cooldown.punch <= 0.0 and _atk.is_empty():
		_jab_buffer = 0.0
		_start_attack(false, 0.0)
	_update_attack(dt)


func _balance(strength: float) -> void:
	var up := global_basis.y
	var av := angular_velocity
	var tilt_v := Vector3(av.x, 0.0, av.z)
	apply_torque((up.cross(Vector3.UP) * 70.0 - tilt_v * 6.0) * strength)
	var fwd := -global_basis.z
	var err := wrapf(facing - atan2(-fwd.x, -fwd.z), -PI, PI)
	apply_torque(Vector3.UP * (err * 18.0 - av.y * 3.0))


func _forward() -> Vector3:
	return Vector3(-sin(facing), 0.0, -cos(facing))


func _ground_check() -> void:
	var q := PhysicsRayQueryParameters3D.create(global_position,
		global_position + Vector3.DOWN * ((BALL_R if state >= BALL else BODY_H * 0.5) + 0.25), 0xFFFFFFFF, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	_grounded = not hit.is_empty()
	_on_oil = _grounded and hit.collider.is_in_group("oil")


# ---- attacks

func _start_attack(heavy: bool, power: float) -> void:
	cooldown.punch = 0.42 if heavy else 0.2
	punch_t[_punch_hand] = PUNCH_TIME
	_punch_hand = 1 - _punch_hand
	var gap := 0.0
	var target := _nearest(2.8, 0.35)  # aim assist, like Gang Beasts' TargetingHandeler
	if target:
		var to := (target.global_position - global_position) * Vector3(1, 0, 1)
		facing = atan2(-to.x, -to.z)
		gap = clampf(to.length() - 1.1, 0.0, 1.6)
	# Step into the punch so it connects at full extension.
	apply_central_impulse(_forward() * ((2.2 if heavy else 1.0) + gap * 2.2) * mass)
	_atk = {t = 0.0, heavy = heavy, power = power, club = holding != null and holding.is_in_group("pins"), hit = []}


func _update_attack(dt: float) -> void:
	if _atk.is_empty():
		return
	_atk.t += dt
	var t0 := 0.06 if _atk.heavy else 0.04  # wind-up, then the fist travels out (Gang Beasts' readying -> punching)
	var t1 := 0.2 if _atk.heavy else 0.15
	if _atk.t >= t0 and _atk.t <= t1:
		var f := _forward()
		var reach := 0.9 + (0.5 if _atk.club else 0.0) + (0.2 if _atk.heavy else 0.0)
		var ext := clampf((_atk.t - t0) / (t1 - t0), 0.0, 1.0)
		var center := global_position + Vector3.UP * 0.3 + f * (0.45 + reach * ext * 0.8)
		for body in _overlap(center, 0.62 if _atk.heavy else 0.5):
			if body == holding or _atk.hit.has(body):
				continue
			if not _atk.heavy and _atk.hit.any(func(x): return x is Beast) and body is Beast:
				continue  # a jab only connects with one person
			_atk.hit.append(body)
			_land(body, f)
	if _atk.t > t1:
		if _atk.hit.is_empty():
			fx.emit("whiff", global_position + _forward(), -8.0)
		_atk.clear()


func _land(body: Node3D, f: Vector3) -> void:
	var dir: Vector3 = (body.global_position - global_position) * Vector3(1, 0, 1)
	dir = dir.normalized() if dir.length() > 0.1 else f
	var at := (global_position + body.global_position) * 0.5 + Vector3.UP * 0.3
	if not body is Beast:
		if body is RigidBody3D and not body.freeze:  # pins and such
			body.apply_central_impulse((dir + Vector3.UP * 0.3) * (5.0 if _atk.heavy else 1.5))
			fx.emit("punch", at, -4.0)
		return
	var b: Beast = body
	var dmg := 12.0
	var force := 4.0
	var lift := 0.15
	var down := 0.0
	var label := ""
	if _atk.heavy:
		var p: float = _atk.power
		dmg = lerpf(20.0, 42.0, p)
		force = lerpf(7.0, 16.0, p)
		lift = lerpf(0.3, 0.6, p)
		down = lerpf(0.3, 1.3, p)
		if p >= 0.99:  # a full charge hits extra hard: two SMASHes and you are a ball
			dmg *= 1.2
			label = "SMASH!"
	else:
		combo = combo + 1 if b == _combo_target and _combo_t < 0.9 else 1
		_combo_target = b
		_combo_t = 0.0
		if combo >= 3:  # jab, jab, FINISHER
			dmg = 22.0
			force = 10.0
			lift = 0.45
			down = 0.8
			label = "COMBO!"
			combo = 0
		elif combo == 2:
			label = "x2"
	if _atk.club:
		dmg *= 1.4
		force *= 1.3
	b.take_hit(pid, dir, dmg, force, lift, down, label)
	fx.emit("smack" if down > 0.0 else "punch", at, 0.0)


func take_hit(by: int, dir: Vector3, dmg: float, force: float, lift := 0.25, down := 0.0, label := "") -> void:
	if state == CARRIED:
		return
	if state == BALL:  # punting a ball sends it rolling, and you get credit for the pins
		apply_central_impulse((dir + Vector3.UP * 0.15) * force * mass * 0.8)
		last_toucher = by
		if force > 6.0:
			projectile_t = 1.5
		return
	if immune > 0.0:
		apply_central_impulse(dir * force * 0.3 * mass)
		return
	health -= dmg
	since_hit = 0.0
	last_hit_by = by
	# Replace most of the current motion so every hit reads clearly, then add a whiplash spin.
	linear_velocity = linear_velocity * 0.3 + (dir + Vector3.UP * lift).normalized() * force
	apply_torque_impulse(Vector3.UP.cross(dir) * force * 0.06)
	stagger = maxf(stagger, 0.25)
	if down > 0.0:
		down_t = maxf(down_t, down)
		physics_material_override = _mat_dive  # tumble and skid to a stop instead of sliding forever
	if holding != null and (down > 0.0 or dmg >= 20.0):  # a real hit (not a jab) makes you drop the ball
		release_hold()
	charging = false
	_atk.clear()  # and interrupts your own punch
	hurt.emit(self, by, dir, clampf(dmg / 40.0, 0.2, 1.0), label)
	if health <= 0.0:
		go_ball(by)


func _start_dive() -> void:
	release_hold()
	charging = false
	state = DIVE
	dive_t = 0.0
	landed_t = 0.0
	_dive_hits.clear()
	physics_material_override = _mat_dive
	var f := _forward()
	linear_velocity = f * 9.5 + Vector3.UP * 3.2
	apply_torque_impulse(Vector3.UP.cross(f) * 1.1)
	cooldown.dive = 1.2
	fx.emit("whiff", global_position, 0.0)


func _sim_dive(dt: float) -> void:
	dive_t += dt
	if _grounded and dive_t > 0.3:
		landed_t += dt
	if landed_t > 0.55 or dive_t > 2.5:
		state = STAND
		physics_material_override = _mat_stand
		stagger = 0.25


func _on_body_entered(other: Node) -> void:
	if other is Beast and other.state <= DIVE:
		var rel: float = (linear_velocity - other.linear_velocity).length()
		if state == DIVE and dive_t < 1.0 and not _dive_hits.has(other) and rel > 3.0:
			_dive_hits.append(other)
			var k := clampf((rel - 3.0) / 6.0, 0.0, 1.0)
			var d := (linear_velocity * Vector3(1, 0, 1)).normalized()
			other.take_hit(pid, d, lerpf(15.0, 35.0, k), lerpf(5.0, 11.0, k), 0.5, lerpf(0.4, 1.0, k), "TACKLE!" if k > 0.5 else "")
			fx.emit("smack", (global_position + other.global_position) * 0.5, 0.0)
		elif state == BALL and projectile_t > 0.0 and rel > 3.5 and other.immune <= 0.0:
			# Super Battle Golf's swing projectile: a launched ball flattens anyone in its path.
			other.take_hit(last_toucher, (linear_velocity * Vector3(1, 0, 1)).normalized(), 45.0, 11.0, 0.6, 1.2, "BOWLED!")
			flattened.emit(last_toucher, other)
		elif state == STAND and down_t > 0.0 and rel > 5.5 and other.immune <= 0.0 and other.down_t <= 0.0:
			# A launched body crashes through whoever it lands on.
			other.take_hit(last_hit_by, (linear_velocity * Vector3(1, 0, 1)).normalized(), 10.0, 5.0, 0.3, 0.5)
			fx.emit("smack", (global_position + other.global_position) * 0.5, -2.0)
	elif other is Beast and state == BALL and projectile_t > 0.0 and other.state == BALL:
		other.last_toucher = last_toucher  # chain reaction: credit flows to the original bowler
		other.projectile_t = 2.0
	elif other.is_in_group("pins") and state == BALL and cooldown.pins_sfx <= 0.0 and linear_velocity.length() > 2.0:
		cooldown.pins_sfx = 1.0
		fx.emit("pins", global_position, 4.0)


# ---- grab, carry, bowl

func _try_grab() -> void:
	var best: Node3D = null
	var best_score := INF
	for body in _overlap(global_position + _forward() * 0.85, 0.75):
		var score: float = body.global_position.distance_to(global_position)
		if body is Beast:
			if body.state == CARRIED or body.held_by != null or (body.state <= DIVE and body.immune > 0.0):
				continue
			score -= 5.0 if body.state == BALL else 0.0  # balls first: that's the whole game
		elif body.is_in_group("pins"):
			if body.freeze:
				continue
			score += 1.0
		else:
			continue
		if score < best_score:
			best = body
			best_score = score
	if best == null:
		return
	holding = best
	hold_time = 0.0
	add_collision_exception_with(best)
	if best is Beast:
		best.held_by = self
		if best.state == BALL:
			best.state = CARRIED
			best.freeze = true
			best.last_toucher = pid
	else:
		best.freeze = true
	fx.emit("thud", global_position, -4.0)


func _update_hold(dt: float) -> void:
	var f := _forward()
	if holding is Beast and holding.state != CARRIED:
		# Dragging someone who is still awake: a spring that gives up after a while (Gang Beasts' grab drain).
		hold_time += dt
		var pt := global_position + Vector3.UP * 0.2 + f * 1.0
		var b: Beast = holding
		b.apply_central_force(((pt - b.global_position) * 40.0 - (b.linear_velocity - linear_velocity) * 5.0) * b.mass)
		if hold_time > 2.5 or b.state == DIVE or b.global_position.distance_to(pt) > 2.0:
			release_hold()
			cooldown.grab = 1.0
		return
	if holding is Beast:
		holding.global_position = global_position + Vector3.UP * 0.45 + f * 0.95
	else:  # a pin held like a club, swung forward on each punch
		var swing := sin(PI * maxf(punch_t[0], punch_t[1]) / PUNCH_TIME)
		holding.global_transform = Transform3D(Basis(Vector3.UP.cross(f).normalized(), 0.5 + swing * 1.1),
			global_position + f * 0.45 + Vector3.UP * 0.1)


func release_hold(throw_v := Vector3.ZERO) -> void:
	if holding == null:
		return
	var h := holding
	holding = null
	cooldown.grab = maxf(cooldown.grab, 0.5)  # don't instantly re-grab what you just bowled or threw
	if not is_instance_valid(h):
		return
	remove_collision_exception_with(h)
	if h is Beast:
		h.held_by = null
		if h.state == CARRIED:
			h.state = BALL
			h.freeze = false
	else:
		h.freeze = false
	h.linear_velocity = linear_velocity + throw_v


func _bowl(power: float) -> void:
	var ball: Beast = holding
	var f := _forward()
	var lane := arena.lane_at(global_position.x)
	if lane >= 0 and f.z < -0.6:  # gentle assist toward the lane's head pin
		var aim := Vector3(arena.lane_x(lane), 0.0, Arena.HEAD_PIN_Z) - global_position
		f = f.lerp(Vector3(aim.x, 0.0, aim.z).normalized(), 0.5).normalized()
	var v := f * lerpf(8.0, 17.0, power)
	release_hold(v - linear_velocity * 0.7)
	ball.global_position = Vector3(global_position.x, global_position.y - 0.2, global_position.z) + f * 1.0
	ball.angular_velocity = Vector3.UP.cross(v) / BALL_R
	ball.projectile_t = 4.0
	ball.last_toucher = pid
	apply_central_impulse(-f * 1.0 * mass)
	fx.emit("bowl", global_position, 2.0)


func _throw_held(power: float) -> void:
	var b: Beast = holding
	release_hold()
	cooldown.grab = 0.6
	b.take_hit(pid, _forward(), 8.0, lerpf(7.0, 13.0, power), lerpf(0.4, 0.6, power), 1.0, "YEET!" if power > 0.7 else "")
	fx.emit("whiff", global_position, 0.0)


# ---- knocked out (curled into a ball)

func go_ball(by: int) -> void:
	state = BALL
	health = 0.0
	ko_time = KO_TIME
	ball_t = 0.0
	ko_by = by
	charging = false
	stagger = 0.0
	last_toucher = 0
	release_hold()
	_set_ball_shape(true)
	if held_by != null:  # knocked out while being dragged: now you're the ball
		state = CARRIED
		freeze = true
		last_toucher = held_by.pid
	knocked_out.emit(self, by)
	fx.emit("ko", global_position, 2.0)


func _sim_ball(inp: Dictionary, dt: float) -> void:
	for k in ["punch", "jump", "grab", "dive"]:
		if _pressed(inp, k):
			ko_time -= 0.12  # mash to wake up sooner (Gang Beasts ReviveCheck)
	ko_time -= dt
	ball_t += dt
	if ball_t < MIN_KO:
		return
	if state == CARRIED:
		if ko_time <= 0.0 and held_by != null:  # woke up in someone's arms: wriggle free
			var carrier := held_by
			carrier.release_hold(Vector3.UP * 3.0)
			carrier.stagger = 0.5
			_wake()
		return
	if ko_time <= 0.0 and projectile_t <= 0.0 and linear_velocity.length() < 2.0:
		_wake()


func _wake() -> void:
	state = STAND
	down_t = 0.0
	health = 70.0
	immune = IMMUNE_TIME
	last_toucher = 0
	projectile_t = 0.0
	freeze = false
	_set_ball_shape(false)
	global_transform = Transform3D(Basis(Vector3.UP, facing), global_position + Vector3.UP * 0.5)
	angular_velocity = Vector3.ZERO
	fx.emit("wake", global_position, 0.0)


func _respawn(pos: Vector3, vel := Vector3.ZERO) -> void:
	release_hold()
	if held_by != null:
		held_by.release_hold()
	global_position = pos
	linear_velocity = vel
	if state >= BALL:
		_wake()
	immune = IMMUNE_TIME + 1.0


func _set_ball_shape(ball: bool) -> void:
	_col.shape = _sphere if ball else _capsule
	physics_material_override = _mat_ball if ball else _mat_stand
	angular_damp = 0.4 if ball else 2.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_AUTO if ball else RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	if not ball:
		center_of_mass = Vector3(0, -0.35, 0)  # bottom-heavy, like a punching clown


func is_rollable() -> bool:
	return state == BALL


# ---- queries

func _overlap(center: Vector3, radius: float) -> Array:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), center)
	q.exclude = [get_rid()]
	var out := []
	for r in get_world_3d().direct_space_state.intersect_shape(q, 12):
		if r.collider is RigidBody3D and not out.has(r.collider):
			out.append(r.collider)
	return out


func _nearest(max_dist: float, min_dot: float) -> Beast:
	var best: Beast = null
	var best_d := max_dist
	var f := _forward()
	for b: Beast in get_tree().get_nodes_in_group("beasts"):
		if b == self or b.state == CARRIED:
			continue
		var to := (b.global_position - global_position) * Vector3(1, 0, 1)
		var d := to.length()
		if d < best_d and d > 0.01 and f.dot(to / d) > min_dot:
			best = b
			best_d = d
	return best


# ================================================================= visuals (host and clients)

func _build_visuals() -> void:
	_vis = Node3D.new()
	add_child(_vis)
	_body_mat = Look.toy(color, 0.3)
	_body_mat.emission_enabled = true
	_body_mat.emission = Color.WHITE
	_body_mat.emission_energy_multiplier = 0.0
	var cap := CapsuleMesh.new()
	cap.radius = BODY_R
	cap.height = BODY_H
	_body = Look.mesh(_vis, cap, _body_mat)
	var belly := Look.toy(color.lightened(0.45), 0.4, false)
	Look.mesh(_body, Look.sphere(0.3, 0.55), belly, Vector3(0, -0.18, -0.22)).scale = Vector3(1, 1, 0.5)
	var white := Look.toy(Color.WHITE, 0.2, false)
	var black := Look.toy(Color("120818"), 0.2, false)
	for s in [-1.0, 1.0]:
		var eye := Look.mesh(_body, Look.sphere(0.12), white, Vector3(s * 0.15, 0.38, -0.33))
		_pupils.append(Look.mesh(eye, Look.sphere(0.06), black, Vector3(0, 0, -0.08)))
		_fists.append(Look.mesh(_vis, Look.sphere(0.16), Look.toy(color.darkened(0.1), 0.3), Vector3(s * 0.55, 0.0, -0.15)))
		var foot := Look.mesh(_vis, Look.sphere(0.15), Look.toy(color.darkened(0.25), 0.4), Vector3(s * 0.2, -0.78, 0))
		foot.scale = Vector3(1.0, 0.6, 1.4)
		_feet.append(foot)

	_overlay = Node3D.new()
	_overlay.top_level = true
	add_child(_overlay)
	_label = Label3D.new()
	_label.text = display_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 44
	_label.outline_size = 12
	_label.pixel_size = 0.005
	_label.modulate = color.lightened(0.3)
	_label.position.y = 1.45
	_overlay.add_child(_label)
	if _bar_mat == null:
		_bar_mat = ShaderMaterial.new()
		_bar_mat.shader = Shader.new()
		_bar_mat.shader.code = BAR_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.12)
	_bar = Look.mesh(_overlay, quad, _bar_mat, Vector3(0, 1.27, 0))
	var star_mesh := PrismMesh.new()
	star_mesh.size = Vector3(0.18, 0.18, 0.05)
	for i in 3:
		_stars.append(Look.mesh(_overlay, star_mesh, Look.neon(Color("ffe14d"), 3.0)))
	var bm := StandardMaterial3D.new()
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.5, 0.9, 1.0, 0.12)
	bm.rim_enabled = true
	_bubble = Look.mesh(_overlay, Look.sphere(0.85), bm)
	_crown = Node3D.new()
	_overlay.add_child(_crown)
	var gold := Look.neon(Color("ffcc33"), 1.2)
	for i in 5:
		var spike := Look.mesh(_crown, star_mesh, gold, Vector3(cos(TAU * i / 5.0) * 0.17, 0.1, sin(TAU * i / 5.0) * 0.17))
		spike.rotation.y = -TAU * i / 5.0 + PI * 0.5
	var ring := CylinderMesh.new()
	ring.top_radius = 0.2
	ring.bottom_radius = 0.2
	ring.height = 0.1
	Look.mesh(_crown, ring, gold)
	_last_pos = global_position


func _process(dt: float) -> void:
	var v := (global_position - _last_pos) / maxf(dt, 0.0001)
	_last_pos = global_position
	_speed = lerpf(_speed, Vector2(v.x, v.z).length(), 1.0 - exp(-dt * 10.0))
	var balled := state >= BALL
	var k := 1.0 - exp(-dt * 16.0)  # limb lag = jelly feel

	if health < _last_health - 1.0:
		_flash = 0.12
	_last_health = health
	_flash = maxf(_flash - dt, 0.0)
	_body_mat.emission_energy_multiplier = 3.0 if _flash > 0.0 else 0.0

	_squash = _squash.lerp(Vector3(1.25, 0.72, 1.25) if balled else Vector3.ONE, k)
	_lean_v += (-180.0 * _lean - 9.0 * _lean_v) * dt
	_lean += _lean_v * dt
	_body.basis = Basis(_lean_axis, clampf(_lean, -0.9, 0.9)) * Basis.from_scale(_squash)
	_hit_shake = maxf(_hit_shake - dt, 0.0)
	_vis.position = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.14 if _hit_shake > 0.0 else Vector3.ZERO
	for p in _pupils:
		p.scale = p.scale.lerp(Vector3(1.6, 0.25, 1.0) if balled else Vector3.ONE, k)

	_phase += dt * _speed * 2.4
	var walk := clampf(_speed / SPEED, 0.0, 1.0) * float(not balled)
	for h in 2:
		var s := -1.0 if h == 0 else 1.0
		var target := Vector3(s * 0.55, 0.0 + sin(_phase + h * PI) * 0.05, -0.15 + sin(_phase + h * PI) * 0.3 * walk)
		if balled:
			target = Vector3(s * 0.38, 0.15, -0.38)
		elif holding != null or net_holding:
			target = Vector3(s * 0.32, 0.4, -0.7)
		elif reaching:
			target = Vector3(s * 0.28, 0.25, -0.8)
		if charging and h == _punch_hand_vis():
			target = Vector3(s * 0.5, 0.35, 0.35) + Vector3(randf(), randf(), randf()) * 0.04 * charge
		if punch_t[h] > 0.0:
			var e := sin(PI * punch_t[h] / PUNCH_TIME)
			target = target.lerp(Vector3(s * 0.12, 0.3, -1.05), e)
		_fists[h].position = _fists[h].position.lerp(target, k if punch_t[h] <= 0.0 else 0.6)
		var grow := 1.0
		if charging and h == _punch_hand_vis():
			grow += charge / FULL_CHARGE * 0.6 + (sin(Time.get_ticks_msec() * 0.03) * 0.12 if charge >= FULL_CHARGE else 0.0)
		_fists[h].scale = Vector3.ONE * grow
		var ft := Vector3(s * 0.2, -0.78 + maxf(0.0, cos(_phase + h * PI)) * 0.14 * walk, sin(_phase + h * PI) * 0.32 * walk)
		if balled:
			ft = Vector3(s * 0.25, -0.38, 0.1)
		_feet[h].position = _feet[h].position.lerp(ft, k)

	# The overlay stays upright even while the body rolls around.
	_overlay.global_position = global_position
	_label.position.y = 1.0 if balled else 1.45
	_bar.visible = not balled and health < MAX_HEALTH - 0.5
	_bar.set_instance_shader_parameter("fill", health / MAX_HEALTH)
	var t := Time.get_ticks_msec() * 0.001
	for i in _stars.size():
		var a := t * 4.0 + TAU * i / _stars.size()
		_stars[i].visible = balled
		_stars[i].position = Vector3(cos(a) * 0.45, 0.85 + sin(t * 6.0 + i) * 0.05, sin(a) * 0.45)
		_stars[i].rotation.y = -a
	_bubble.visible = immune > 0.0 and not balled
	_bubble.scale = Vector3.ONE * (1.0 + sin(t * 10.0) * 0.03)
	_crown.visible = leader and not balled
	_crown.position.y = 1.0 + sin(t * 3.0) * 0.05


func react(dir: Vector3, power: float, attacker := false) -> void:
	## Visual-only hit reaction, run on every peer: hit-stop shake, plus whiplash and squash for the victim.
	_hit_shake = 0.05 if attacker else 0.08 + 0.1 * power
	if attacker:
		return
	var local := global_basis.inverse() * dir
	local.y = 0.0
	if local.length() > 0.01:
		_lean_axis = Vector3.UP.cross(local.normalized())
		_lean_v += 7.0 + 9.0 * power
	_squash = Vector3(1.0 + 0.25 * power, 1.0 - 0.25 * power, 1.0 + 0.25 * power)
	_flash = 0.1


func _punch_hand_vis() -> int:
	return _punch_hand
