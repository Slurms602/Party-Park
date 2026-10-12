extends SceneTree
## Tuning check: bowl human-ish throws (off-centre start, aim error, mixed power) on every map and
## print the strike rate. Sunset Lanes must be clearly harder than the classic alley.
## Run from the repo root: godot --headless --path game -s minigames/bowling/tests/strike_rate.gd

const DT := 1.0 / 60.0
const ROLLS := 36


func _initialize() -> void:
	Engine.time_scale = 4.0  # each physics step is still 1/60 s of game time
	Engine.physics_ticks_per_second = 240
	Engine.max_physics_steps_per_frame = 64
	_run.call_deferred()


func _run() -> void:
	var rates := {}
	for map_id in preload("../minigame.gd").MAPS:
		rates[map_id] = await _measure(map_id)
	var ok: bool = rates.sunset < rates.classic * 0.7
	print("%s  sunset is harder than classic" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


func _measure(map_id: String) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var world := Node3D.new()
	root.add_child(world)
	var arena: BowlingArena = Arena.make(map_id)
	world.add_child(arena)
	arena.setup(true)
	var kinds := []
	var pins := [0]
	arena.roll_finished.connect(func(_lane, _bowler, knocked, kind):
		kinds.append(kind)
		pins[0] += knocked)
	var pairs := []
	for i in arena.lane_count:
		pairs.append([_beast(world, arena, i * 2 + 1), _beast(world, arena, i * 2 + 2)])
	var all := []
	for p in pairs:
		all.append_array(p)
	while kinds.size() < ROLLS:
		var powers := []
		for i in pairs.size():
			var x := arena.lane_x(i) + rng.randf_range(-0.3, 0.3) * arena.lane_w
			pairs[i][0]._respawn(Vector3(x, 0.9, 2.2))
			pairs[i][1]._respawn(Vector3(x, 0.9, 1.0))
			pairs[i][0].facing = deg_to_rad(rng.randf_range(-6.0, 6.0))
			powers.append(rng.randf_range(0.5, 1.0))
		await _drive(arena, all, {}, {}, 30)
		for p in pairs:
			p[1].immune = 0.0
			p[1].take_hit(p[0].pid, Vector3.FORWARD, 500.0, 0.5)
		await _drive(arena, all, {}, {}, 20)
		await _drive(arena, all, {grab = true}, {}, 3)
		for f in 60:  # each bowler lets go once their own wind-up reaches their power
			var inp := {}
			for i in pairs.size():
				inp[pairs[i][0]] = {grab = true, punch = f < powers[i] * 54.0}
			await _drive(arena, all, {}, inp, 1)
		var before := kinds.size()
		for f in 600:
			if kinds.size() - before >= pairs.size():
				break
			await _drive(arena, all, {}, {}, 1)
		for lane in arena.lanes:
			lane.ball = null
			lane.rerack = 0.01
		await _drive(arena, all, {}, {}, 100)
	world.free()
	var strikes := kinds.count("strike")
	var rate := float(strikes) / kinds.size()
	print("%-8s strikes %2d / %d = %3d%%   avg pins %.1f" % [map_id, strikes, kinds.size(), roundi(rate * 100), float(pins[0]) / kinds.size()])
	return rate


func _beast(world: Node3D, arena: BowlingArena, id: int) -> Beast:
	var b := Beast.new()
	world.add_child(b)
	b.setup(id, {name = "P%d" % id, color = Color.WHITE}, arena, true)
	b.global_position = Vector3(0, 0.9, 6.0)
	return b


func _drive(arena: BowlingArena, beasts: Array, inp: Dictionary, per: Dictionary, frames: int) -> void:
	# `inp` goes to every bowler (odd ids); `per` overrides it per beast.
	for f in frames:
		for b: Beast in beasts:
			b.sim(per.get(b, inp if b.pid % 2 == 1 else {}), DT)
		arena.server_update(DT, beasts)
		await physics_frame
