extends SceneTree
## Touch controls: GRAB is a toggle, so you can wind up PUNCH with the same thumb and still bowl.
## Run from the repo root: godot --headless --path game -s tests/test_touch_grab.gd

const DT := 1.0 / 60.0
var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in ["left", "right", "up", "down", "jump", "punch", "grab", "dive", "pause"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
	var world := Node3D.new()
	root.add_child(world)
	var arena := Arena.new()
	world.add_child(arena)
	arena.setup(true)
	var x := arena.lane_x(1)
	var me := _beast(world, arena, 1, Vector3(x, 0.9, 2.2))
	var friend := _beast(world, arena, 2, Vector3(x, 0.9, 1.0))
	var tc := TouchControls.new()
	tc.me_id = 1
	root.add_child(tc)
	await _drive(me, friend, arena, 40)
	friend.take_hit(1, Vector3.FORWARD, 500.0, 0.5)
	await _drive(me, friend, arena, 20)

	tc._set_grab(true)  # tap GRAB once
	await _drive(me, friend, arena, 5)
	_check(me.holding == friend, "tapping GRAB picks the ball up")
	_check(tc._buttons[0].get_child(0).text == "BOWL!", "PUNCH turns into BOWL! while carrying")
	Input.action_press("punch")  # same thumb moves to PUNCH and holds it
	await _drive(me, friend, arena, 50)
	_check(me.holding == friend and me.charging, "still carrying while winding up (no thumb on GRAB)")
	Input.action_release("punch")
	await _drive(me, friend, arena, 3)
	_check(me.holding == null and friend.linear_velocity.z < -8.0, "letting go of PUNCH bowls them (vz=%.1f)" % friend.linear_velocity.z)
	_check(not Input.is_action_pressed("grab"), "GRAB switches itself off after the bowl")

	print("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails)
	quit(1 if _fails else 0)


func _beast(world: Node3D, arena: Arena, id: int, pos: Vector3) -> Beast:
	var b := Beast.new()
	world.add_child(b)
	b.setup(id, {name = "P%d" % id, color = Color.WHITE}, arena, true)
	b.global_position = pos
	return b


func _drive(me: Beast, other: Beast, arena: Arena, frames: int) -> void:
	for f in frames:
		await process_frame  # lets TouchControls._process watch what we're holding
		await physics_frame  # then step inside the physics frame, like the game (physics runs on its own thread)
		me.sim({grab = Input.is_action_pressed("grab"), punch = Input.is_action_pressed("punch")}, DT)
		other.sim({}, DT)
		arena.server_update(DT, [me, other])


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1
