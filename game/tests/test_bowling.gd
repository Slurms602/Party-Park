extends SceneTree
## Headless check of the core loop through the real input path:
## knockout -> grab -> charge -> bowl -> pins scored -> ball return -> re-rack.
## Run from the repo root: godot --headless --path game -s tests/test_bowling.gd

const DT := 1.0 / 60.0
var _fails := 0
var _arena: Arena


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var arena := Arena.new()
	world.add_child(arena)
	arena.setup(true)
	_arena = arena
	var rolls := []
	arena.roll_finished.connect(func(lane, bowler, knocked, kind): rolls.append([lane, bowler, knocked, kind]))
	var x := arena.lane_x(1)
	var bowler := _beast(world, arena, 1, Vector3(x, 0.9, 2.2))
	var victim := _beast(world, arena, 2, Vector3(x, 0.9, 1.0))
	var all := [bowler, victim]
	await _drive(all, {}, 40)

	victim.take_hit(1, Vector3.FORWARD, 500.0, 0.5)
	_check(victim.state == Beast.BALL, "a knocked-out player curls into a ball")
	await _drive(all, {}, 20)

	await _drive(all, {grab = true}, 3)
	_check(bowler.holding == victim and victim.state == Beast.CARRIED, "grabbing the ball picks it up")

	await _drive(all, {grab = true, punch = true}, 50)
	_check(bowler.charging and bowler.charge > 0.7, "holding punch charges the bowl")
	await _drive(all, {grab = true}, 1)
	_check(bowler.holding == null and victim.state == Beast.BALL and victim.linear_velocity.z < -8.0,
		"releasing punch bowls the ball down the lane (vz=%.1f)" % victim.linear_velocity.z)

	for i in 600:
		if not rolls.is_empty():
			break
		await _drive(all, {}, 1)
	_check(rolls.size() == 1, "the roll is scored")
	if rolls.size() == 1:
		_check(rolls[0][0] == 1 and rolls[0][1] == 1, "credited to the bowler on lane 2")
		_check(rolls[0][2] > 0, "pins were knocked down: %d (%s)" % [rolls[0][2], rolls[0][3]])

	for i in 300:
		if victim.state == Beast.STAND:
			break
		await _drive(all, {}, 1)
	_check(victim.state == Beast.STAND and victim.immune > 0.0, "the bowled player comes back awake and immune")

	await _drive(all, {}, int((Arena.RERACK_PARTIAL + 2.0) / DT))
	_check(arena.standing(arena.lanes[1]) == 10, "pins are re-racked")

	# Foul: carry the ball past the line and bowl from there.
	bowler.global_position = Vector3(x, 0.9, -1.5)
	victim.immune = 0.0
	victim.global_position = Vector3(x, 0.9, -2.6)
	await _drive(all, {}, 30)
	victim.take_hit(1, Vector3.FORWARD, 500.0, 0.5)
	await _drive(all, {}, 20)
	await _drive(all, {grab = true}, 3)
	await _drive(all, {grab = true, punch = true}, 50)
	await _drive(all, {grab = true}, 1)
	for i in 600:
		if rolls.size() > 1:
			break
		await _drive(all, {}, 1)
	_check(rolls.size() == 2 and rolls[1][3] == "foul", "bowling from past the foul line is a foul (%s)" % [rolls.slice(1)])

	print("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails)
	quit(1 if _fails else 0)


func _beast(world: Node3D, arena: Arena, id: int, pos: Vector3) -> Beast:
	var b := Beast.new()
	world.add_child(b)
	b.setup(id, {name = "P%d" % id, color = Color.WHITE}, arena, true)
	b.global_position = pos
	return b


func _drive(beasts: Array, inp: Dictionary, frames: int) -> void:
	for f in frames:
		beasts[0].sim(inp, DT)
		for b in beasts.slice(1):
			b.sim({}, DT)
		_arena.server_update(DT, beasts)
		await physics_frame


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1
