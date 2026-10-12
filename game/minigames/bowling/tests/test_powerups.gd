extends SceneTree
## Item boxes and every power-up, through the real sim.
## Run from the repo root: godot --headless --path game -s minigames/bowling/tests/test_powerups.gd

const DT := 1.0 / 60.0
var _fails := 0
var _arena: BowlingArena
var _pu: Powerups


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	_arena = BowlingArena.new()
	world.add_child(_arena)
	_arena.setup(true)
	_pu = Powerups.new()
	world.add_child(_pu)
	_pu.setup(_arena, true)
	var got := []
	_pu.picked.connect(func(_b, kind): got.append(kind))
	var me := _beast(world, 1, Vector3(0, 0.9, 4.0))
	var foe := _beast(world, 2, Vector3(3, 0.9, 4.0))
	var all := [me, foe]
	me.threw.connect(_pu.spawn_ball)

	# Boxes appear after a few seconds and hand out an item on touch.
	await _drive(all, {}, {}, int(7.5 / DT))
	var box: Node3D = _pu._boxes[1]
	_check(box.visible, "item boxes spawn on the back floor")
	me.global_position = box.global_position + Vector3(0, 0.9, 0)
	await _drive(all, {}, {}, 5)
	_check(me.item != "" and got.size() == 1 and not box.visible, "touching a box gives an item (%s)" % me.item)
	for i in _pu._boxes.size():  # keep the rest of the test free of stray pickups
		_pu._boxes[i].visible = false
		_pu._timers[i] = 999.0

	# BOWLING BALL: thrown at someone 5 m away it hurts a lot.
	_reset(me, Vector3(0, 0.9, 6.0), foe, Vector3(0, 0.9, 1.0))
	_pu.give(me, "ball")
	await _drive(all, {}, {}, 20)
	await _drive(all, {punch = true}, {}, 30)
	await _drive(all, {}, {}, 1)
	_check(me.item == "", "punch throws the bowling ball")
	await _drive(all, {}, {}, 40)
	_check(foe.health <= 70.0, "the ball hits hard (health %.0f)" % foe.health)

	# BIG GLOVES: a jab does 1.5x.
	_reset(me, Vector3(0, 0.9, 6.0), foe, Vector3(0, 0.9, 5.0))
	_pu.give(me, "gloves")
	await _drive(all, {}, {}, 20)
	await _drive(all, {punch = true}, {}, 2)
	await _drive(all, {}, {}, 20)
	_check(absf(foe.health - 82.0) < 0.5, "big gloves jab does 18 (health %.0f)" % foe.health)

	# GIANT PIN: one swing is a smash, and it breaks after 3.
	_reset(me, Vector3(0, 0.9, 6.0), foe, Vector3(0, 0.9, 4.6))
	_pu.give(me, "giant_pin")
	await _drive(all, {}, {}, 20)
	await _drive(all, {punch = true}, {}, 2)
	await _drive(all, {}, {}, 20)
	_check(foe.health <= 58.0 and foe.down_t > 0.0, "a giant pin swing smashes (health %.0f)" % foe.health)
	for i in 2:
		await _drive(all, {punch = true}, {}, 2)
		await _drive(all, {}, {}, 30)
	_check(me.item == "", "the giant pin is gone after 3 swings")

	# TURBO SHOES: faster running.
	_reset(me, Vector3(-6, 0.9, 8.0), foe, Vector3(6, 0.9, 1.0))
	await _drive(all, {move = Vector2(1, 0)}, {}, 60)
	var plain := me.linear_velocity.length()
	_pu.give(me, "shoes")
	await _drive(all, {move = Vector2(1, 0)}, {}, 30)
	_check(me.linear_velocity.length() > plain * 1.3, "turbo shoes run faster (%.1f vs %.1f)" % [me.linear_velocity.length(), plain])

	# STICKY GRIP: a carried ball doesn't wake up.
	var x := _arena.lane_x(1)
	_reset(me, Vector3(x, 0.9, 2.2), foe, Vector3(x, 0.9, 1.0))
	_pu.give(me, "sticky")
	await _drive(all, {}, {}, 20)
	foe.take_hit(1, Vector3.FORWARD, 500.0, 0.5)
	await _drive(all, {}, {}, 20)
	await _drive(all, {grab = true}, {}, 3)
	var ko := foe.ko_time
	await _drive(all, {grab = true}, {foe: {punch = true}}, 120)
	_check(foe.state == Beast.CARRIED and foe.ko_time == ko, "sticky grip: the carried ball's wake-up clock stops")

	# GOLDEN BALL + BUMPERS on the next bowl: a ball aimed at the gutter still reaches the pins, golden.
	me.item = ""
	_pu.give(me, "bumpers")
	me.facing = -0.42  # aimed well right of the head pin: a gutter ball without bumpers
	await _drive(all, {grab = true, punch = true}, {}, 50)
	await _drive(all, {grab = true}, {}, 1)
	_check(_arena.lanes[1].bumpers, "bumpers rise on your lane when you bowl")
	var rolls := []
	_arena.roll_finished.connect(func(_l, _b, knocked, _k): rolls.append(knocked))
	for i in 600:
		if not rolls.is_empty():
			break
		await _drive(all, {}, {}, 1)
	_check(not rolls.is_empty() and rolls[0] > 0 and not _arena.lanes[1].bumpers,
		"a gutter-bound bowl bounces off the bumpers into the pins (%s), then they drop" % [rolls])

	print("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails)
	quit(1 if _fails else 0)


func _reset(a: Beast, pa: Vector3, b: Beast, pb: Vector3) -> void:
	a._respawn(pa)
	b._respawn(pb)
	a.item = ""
	a.immune = 0.0
	b.immune = 0.0
	b.health = Beast.MAX_HEALTH
	b.down_t = 0.0
	a.facing = atan2(-(pb - pa).x, -(pb - pa).z)


func _beast(world: Node3D, id: int, pos: Vector3) -> Beast:
	var b := Beast.new()
	world.add_child(b)
	b.setup(id, {name = "P%d" % id, color = Color.WHITE}, _arena, true)
	b.global_position = pos
	return b


func _drive(beasts: Array, inp: Dictionary, per: Dictionary, frames: int) -> void:
	for f in frames:
		beasts[0].sim(inp, DT)
		for b in beasts.slice(1):
			b.sim(per.get(b, {}), DT)
		_arena.server_update(DT, beasts)
		_pu.server_update(DT, beasts)
		await physics_frame


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1
