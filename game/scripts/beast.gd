class_name Beast
extends RigidBody3D
## A wobbly jelly bowler. The host runs sim() every physics tick. Clients get a frozen copy
## that game.gd moves to match snapshots, and _process() animates the limbs from the same state on both sides.

signal knocked_out(victim: Beast, by: int)
signal flattened(by: int, victim: Beast)  # a bowled ball ran someone over
signal fx(clip: String, pos: Vector3, volume_db: float)
signal hurt(victim: Beast, by: int, dir: Vector3, power: float, label: String)  # drives hit reactions on every peer
signal threw(by: Beast, pos: Vector3, vel: Vector3)  # a BOWLING BALL item left our hands

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
var net_carrying := false  # ...and whether it's a ball
var immune := 0.0
var leader := false
var item := ""  # Powerups.KINDS id, "" for none
var item_t := 0.0  # seconds left before it expires
var item_uses := 0  # GIANT PIN swings left
var golden := false  # bowled with GOLDEN BALL: this roll scores double
var out := false  # knocked out of a minigame round (Sumo Ring): hidden, frozen and skipped until the next match

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
var _assist := false  # this player is on a touch screen (input flag): wider aim help
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
var skin := {}
var foul := false  # this ball was last launched from past the foul line
var _model: BowlerModel
var _overlay: Node3D
var _stars: Array[MeshInstance3D] = []
var _bubble: MeshInstance3D
var _crown: Node3D
var _label: Label3D
var _marker: Node3D  # bouncing GRAB! arrow over a downed player
var _bar: MeshInstance3D
var _item_label: Label3D
var _held_ball: Node3D
var _giant_pin: MeshInstance3D
var _gold: MeshInstance3D
var _last_pos := Vector3.ZERO
var _speed := 0.0

const BAR_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled;
uniform float fill = 1.0;
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
static var _bar_shader: Shader
var _bar_mat: ShaderMaterial


func setup(id: int, info: Dictionary, a: Arena, simulate: bool) -> void:
	pid = id
	display_name = info.name
	color = info.color
	skin = Skins.sanitize(info.get("skin", {}))
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
	if item != "":
		item_t -= dt
		if item_t <= 0.0:
			item = ""
	_ground_check()
	match state:
		STAND: _sim_stand(inp, dt)
		DIVE: _sim_dive(dt)
		BALL, CARRIED: _sim_ball(inp, dt)
	_prev = inp
	_assist = inp.get("assist", false)
	if state != CARRIED and arena.in_pit(global_position):
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
	var speed := SPEED * (0.5 if charging else 1.0) * (0.9 if holding is Beast else 1.0) * (1.4 if item == "shoes" else 1.0)
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
	if arena.buttons(self, inp, dt):
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
			elif item == "ball":
				_throw_ball(power)
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
	var target := _nearest(3.6, 0.0) if _assist else _nearest(2.8, 0.35)  # aim assist, like Gang Beasts' TargetingHandeler
	if target:
		var to := (target.global_position - global_position) * Vector3(1, 0, 1)
		facing = atan2(-to.x, -to.z)
		gap = clampf(to.length() - 1.1, 0.0, 1.6)
	# Step into the punch so it connects at full extension.
	apply_central_impulse(_forward() * ((2.2 if heavy else 1.0) + gap * 2.2) * mass)
	var giant := item == "giant_pin" and holding == null
	if giant:
		item_uses -= 1
	_atk = {t = 0.0, heavy = heavy, power = power, club = holding != null and holding.is_in_group("pins"), giant = giant, hit = []}


func _update_attack(dt: float) -> void:
	if _atk.is_empty():
		return
	_atk.t += dt
	var t0 := 0.06 if _atk.heavy else 0.04  # wind-up, then the fist travels out (Gang Beasts' readying -> punching)
	var t1 := 0.2 if _atk.heavy else 0.15
	if _atk.t >= t0 and _atk.t <= t1:
		var f := _forward()
		var reach := 0.9 + (0.5 if _atk.club else 0.0) + (0.2 if _atk.heavy else 0.0) + (0.9 if _atk.giant else 0.0)
		var ext := clampf((_atk.t - t0) / (t1 - t0), 0.0, 1.0)
		var center := global_position + Vector3.UP * 0.3 + f * (0.45 + reach * ext * 0.8)
		for body in _overlap(center, 0.8 if _atk.giant else 0.62 if _atk.heavy else 0.5):
			if body == holding or _atk.hit.has(body):
				continue
			if not _atk.heavy and _atk.hit.any(func(x): return x is Beast) and body is Beast:
				continue  # a jab only connects with one person
			_atk.hit.append(body)
			_land(body, f)
	if _atk.t > t1:
		if _atk.hit.is_empty():
			fx.emit("whiff", global_position + _forward(), -8.0)
		if _atk.giant and item_uses <= 0:
			item = ""
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
	if b.state == BALL:
		b.foul = global_position.z < 0.0  # punting counts too, from behind the line
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
	if _atk.giant:  # every GIANT PIN swing hits like a full-charge smash
		dmg = maxf(dmg, 42.0)
		force = maxf(force, 15.0)
		lift = 0.55
		down = maxf(down, 1.2)
		label = "BONK!"
	if item == "gloves":
		dmg *= 1.5
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
	health -= dmg * arena.damage
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
		other.foul = foul
		other.projectile_t = 2.0
	elif other.is_in_group("pins") and state == BALL and cooldown.pins_sfx <= 0.0 and linear_velocity.length() > 2.0:
		cooldown.pins_sfx = 1.0
		fx.emit("pins", global_position, 4.0)


# ---- grab, carry, bowl

func _try_grab() -> void:
	var best: Node3D = null
	var best_score := INF
	for body in _overlap(global_position + _forward() * 0.85, 1.05 if _assist else 0.75):
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
			if item == "sticky":
				item_t = minf(item_t, 8.0)  # they can't wake up in your arms, for up to 8 s
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
		# Move toward the hold point at a capped speed: a carried (kinematic) ball that teleports when you spin
		# would hit bystanders at hundreds of m/s and fling them into orbit.
		var target := global_position + Vector3.UP * 0.45 + f * 0.95
		var cur: Vector3 = holding.global_position
		holding.global_position = target if cur.distance_to(target) > 3.0 else cur + (target - cur).limit_length(12.0 * dt)
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
			if item == "sticky":
				item = ""
	else:
		h.freeze = false
	h.linear_velocity = linear_velocity + throw_v


func _bowl(power: float) -> void:
	var ball: Beast = holding
	var f := arena.aim(self, _forward())
	var v := f * lerpf(8.0, 17.0, power)
	release_hold(v - linear_velocity * 0.7)
	ball.global_position = Vector3(global_position.x, global_position.y - 0.2, global_position.z) + f * 1.0
	ball.angular_velocity = Vector3.UP.cross(v) / BALL_R
	ball.projectile_t = 4.0
	ball.last_toucher = pid
	arena.launched(self, ball)
	apply_central_impulse(-f * 1.0 * mass)
	fx.emit("bowl", global_position, 2.0)


func _throw_ball(power: float) -> void:
	item = ""
	var f := _forward()
	var target := _nearest(14.0, 0.8)  # a little help toward whoever you're facing
	if target:
		f = f.lerp(((target.global_position - global_position) * Vector3(1, 0, 1)).normalized(), 0.6).normalized()
	threw.emit(self, global_position + f * 0.9 + Vector3.UP * 0.35, f * lerpf(12.0, 20.0, power) + Vector3.UP * lerpf(2.5, 1.2, power))
	apply_central_impulse(-f * 1.5 * mass)
	fx.emit("bowl", global_position, 0.0)


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
	if state == CARRIED and held_by != null and held_by.item == "sticky":
		return  # STICKY GRIP: the wake-up clock stops while they carry you
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
	golden = false
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


func set_out() -> void:
	release_hold()
	if held_by != null:
		held_by.release_hold()
	out = true
	visible = false
	freeze = true
	global_position = Vector3(0, -40, 0)


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
	_model = BowlerModel.new()
	add_child(_model)
	_model.build(color, skin)

	_overlay = Node3D.new()
	_overlay.top_level = true
	add_child(_overlay)
	_label = Label3D.new()
	_label.text = display_name
	_label.font = Look.font()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 44
	_label.outline_size = 14
	_label.pixel_size = 0.005
	_label.modulate = color.lightened(0.3)
	_label.position.y = 1.45
	_overlay.add_child(_label)
	if _bar_shader == null:
		_bar_shader = Shader.new()
		_bar_shader.code = BAR_SHADER
	_bar_mat = ShaderMaterial.new()
	_bar_mat.shader = _bar_shader
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
	_marker = Node3D.new()
	_overlay.add_child(_marker)
	var arrow := PrismMesh.new()
	arrow.size = Vector3(0.36, 0.3, 0.08)
	Look.mesh(_marker, arrow, Look.neon(Color("ffe14d"), 2.5)).rotation.z = PI
	var grab := Label3D.new()
	grab.text = "GRAB!"
	grab.font = Look.font(true)
	grab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	grab.no_depth_test = true
	grab.font_size = 40
	grab.outline_size = 12
	grab.pixel_size = 0.005
	grab.modulate = Color("ffe14d")
	grab.position.y = 0.32
	_marker.add_child(grab)
	# Items: a tag over your head so everyone knows what you've got, plus the held ball / giant pin.
	_item_label = Label3D.new()
	_item_label.font = Look.font(true)
	_item_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_item_label.no_depth_test = true
	_item_label.font_size = 34
	_item_label.outline_size = 12
	_item_label.pixel_size = 0.005
	_item_label.position.y = 1.72
	_overlay.add_child(_item_label)
	_held_ball = Powerups.ball_visual()
	_overlay.add_child(_held_ball)
	_giant_pin = Look.mesh(_overlay, Arena.pin_mesh(), Arena.pin_material())
	var gm := StandardMaterial3D.new()
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(1.0, 0.8, 0.2, 0.25)
	_gold = Look.mesh(_overlay, Look.sphere(0.8), gm)
	Look.no_shadow(_overlay, [] if Look.fast() else _held_ball.find_children("*", "GeometryInstance3D", true, false) + [_giant_pin])  # labels, bars, stars...
	_last_pos = global_position


func _process(dt: float) -> void:
	var v := (global_position - _last_pos) / maxf(dt, 0.0001)
	_last_pos = global_position
	_speed = lerpf(_speed, Vector2(v.x, v.z).length(), 1.0 - exp(-dt * 10.0))
	var balled := state >= BALL
	var has_ball := item == "ball" and not balled
	_model.pose(dt, {speed = _speed, balled = balled, holding = holding != null or net_holding or has_ball, reaching = reaching,
		charging = charging, charge = charge / FULL_CHARGE, punch = [punch_t[0] / PUNCH_TIME, punch_t[1] / PUNCH_TIME],
		hand = _punch_hand, low = health < 25.0 and not balled, big = item == "gloves"})

	# The overlay stays upright even while the body rolls around.
	_overlay.global_position = global_position
	_label.position.y = 1.0 if balled else 1.45
	_bar.visible = not balled and health < MAX_HEALTH - 0.5
	_bar_mat.set_shader_parameter("fill", health / MAX_HEALTH)
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
	_marker.visible = state == BALL and _speed < 3.0
	if _overlay.has_meta("ring"):
		_overlay.get_meta("ring").visible = not balled
	_marker.position.y = 1.55 + absf(sin(t * 5.0)) * 0.2
	var kind: Dictionary = Powerups.KINDS.get(item, {})
	_item_label.visible = not kind.is_empty() and not balled
	if _item_label.visible:
		_item_label.text = kind.name
		_item_label.modulate = kind.color
	var f := _forward()
	_held_ball.visible = has_ball
	_held_ball.position = f * -0.3 + Vector3.UP * 0.85 if charging else f * 0.75 + Vector3.UP * 0.35  # wound up overhead
	_giant_pin.visible = item == "giant_pin" and not balled
	if _giant_pin.visible:  # carried over the shoulder, swung down on each punch
		var swing := sin(PI * maxf(punch_t[0], punch_t[1]) / PUNCH_TIME)
		_giant_pin.transform = Transform3D(Basis(Vector3.UP.cross(f).normalized(), 0.3 + swing * 1.3).scaled(Vector3.ONE * 1.8),
			f * 0.4 + Vector3.UP * 0.1)
	_gold.visible = golden or (item == "golden" and not balled)


func mark_local() -> void:
	## A glowing ring under your own bowler so you never lose yourself in the pile.
	var ring := TorusMesh.new()
	ring.inner_radius = 0.5
	ring.outer_radius = 0.6
	var r := Look.mesh(_overlay, ring, Look.neon(color.lightened(0.2), 2.0), Vector3(0, -0.72, 0))
	r.scale = Vector3(1, 0.3, 1)
	r.set_meta("local_ring", true)
	_overlay.set_meta("ring", r)


func react(dir: Vector3, power: float, attacker := false) -> void:
	## Visual-only hit reaction, run on every peer.
	if attacker:
		_model.shake(0.05)
	else:
		_model.hit(global_basis.inverse() * dir, power)
