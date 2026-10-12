extends SceneTree
## Draw calls for a fixed gameplay view (8 bowlers, a full rack, the match camera), per graphics level and map.
## Phones are limited by draw calls more than anything; this keeps the Fast level honest.
## Run: godot --path game --rendering-method mobile -s tests/render_bench.gd -- <classic|sunset> <high|classic|fast>

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefs: Node = root.get_node("Prefs")
	prefs.graphics = args[1]
	prefs.apply()
	var world := Node3D.new()
	root.add_child(world)
	var arena := Arena.make(args[0])
	world.add_child(arena)
	arena.setup(true)
	for i in 8:
		var b := Beast.new()
		world.add_child(b)
		b.setup(i + 1, {name = "P%d" % i, color = Color.from_hsv(i / 8.0, 0.7, 0.95), skin = Skins.PRESETS.values()[i % Skins.PRESETS.size()]}, arena, false)
		b.global_position = Vector3((i % 4 - 1.5) * 2.5, 0.9, 3.0 + (i / 4) * 2.5)
	var cam := Camera3D.new()
	cam.fov = 55.0
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 7.5, 13.0), Vector3(0, 7.5, 13.0) + arena.cam_look.normalized())
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for f in 6:
		await process_frame
	var draws := 0.0
	var cpu := 0.0
	var gpu := 0.0
	var n := 14
	for f in n:
		await process_frame
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	print("RENDER %s map, %s graphics: %d draw calls, render cpu %.1f ms, gpu %.1f ms (software GPU: compare, don't read as phone ms)" % [args[0], args[1], draws / n, cpu / n, gpu / n])
	quit()
