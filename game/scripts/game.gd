class_name Game
extends Node3D
## One match. The host simulates and scores everything and sends snapshots at 30 Hz.
## Clients send input and draw snapshots about 100 ms behind, interpolating between them.

const SNAP_INTERVAL := 1.0 / 30.0
const INTERP_DELAY := 0.1
const STRIKE_BONUS := 10
const SPARE_BONUS := 5
const FLATTEN_POINTS := 2
const COMEBACK_GAP := 30  # Super Battle Golf-style comeback bonus for whoever is far behind

var arena: Arena
var hud: Hud
var cam: Camera3D
var beasts := {}  # pid -> Beast
var inputs := {}  # pid -> latest input (host)
var scores := {}  # pid -> {total, rolls, streak}
var time_left := 180.0
var server := false
var over := false
var _server_time := 0.0
var _snap_acc := 0.0
var _snaps: Array = []  # client: [time, beasts, time_left]
var _pin_snaps: Array = []  # client: [time, half-float pin transforms]
var _clock := 0.0
var _shake := 0.0
var _follow: Beast = null
var _follow_t := 0.0
var _ready_peers := {}  # host: clients whose Game node exists, so RPCs to it can land


func _ready() -> void:
	server = Net.is_host()
	time_left = Net.match_seconds
	arena = Arena.new()
	add_child(arena)
	arena.setup(server)
	arena.roll_finished.connect(_on_roll)
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.position = Vector3(0, 10, 16)
	add_child(cam)
	cam.current = true
	hud = Hud.new()
	add_child(hud)
	Net.players_changed.connect(_sync_roster)
	_sync_roster()
	if not server:
		_hello.rpc_id(1)


func _sync_roster() -> void:
	for pid in Net.players:
		if not beasts.has(pid):
			var b := Beast.new()
			add_child(b)
			b.setup(pid, Net.players[pid], arena, server)
			b.global_position = arena.spawn_point(beasts.size())
			b.immune = Beast.IMMUNE_TIME
			beasts[pid] = b
			if server:
				b.knocked_out.connect(_on_ko)
				b.flattened.connect(_on_flattened)
				b.fx.connect(func(clip, pos, vol): _send(_ev_fx, [clip, pos, vol]))
		if not scores.has(pid):
			scores[pid] = {total = 0, rolls = [], streak = 0}
	for pid in beasts.keys():
		if not Net.players.has(pid):
			var b: Beast = beasts[pid]
			b.release_hold()
			if b.held_by:
				b.held_by.release_hold()
			beasts.erase(pid)
			b.queue_free()
	for pid in _ready_peers.keys():
		if not Net.players.has(pid):
			_ready_peers.erase(pid)
	_refresh_boards()
	if server:
		_send(_ev_scores, [scores])


# ================================================================= host

func _physics_process(dt: float) -> void:
	_send_local_input()
	if not server:
		return
	_server_time += dt
	for pid in beasts:
		var b: Beast = beasts[pid]
		var inp: Dictionary = Bot.think(b, arena, dt) if Net.players[pid].bot else inputs.get(pid, {})
		b.sim(inp, dt)
	arena.server_update(dt, beasts.values())
	if not over:
		time_left -= dt
		if time_left <= 0.0:
			time_left = 0.0
			_end_match()
	var lead := _leader()
	for pid in beasts:
		beasts[pid].leader = pid == lead
	_snap_acc += dt
	if _snap_acc >= SNAP_INTERVAL:
		_snap_acc = 0.0
		_send(_snap, [_server_time, _pack_beasts(), time_left], false)
		_send(_snap_pins, [_server_time, arena.pin_snapshot()], false)


func _send_local_input() -> void:
	var mv := Input.get_vector("left", "right", "up", "down")
	var bits := int(Input.is_action_pressed("jump")) | int(Input.is_action_pressed("punch")) << 1 \
		| int(Input.is_action_pressed("grab")) << 2 | int(Input.is_action_pressed("dive")) << 3
	if hud.paused:
		mv = Vector2.ZERO
		bits = 0
	if server:
		_client_input(mv, bits)
	else:
		_client_input.rpc_id(1, mv, bits)


@rpc("any_peer", "call_local", "unreliable_ordered")
func _client_input(mv: Vector2, bits: int) -> void:
	var pid := multiplayer.get_remote_sender_id()
	if pid == 0:
		pid = 1
	inputs[pid] = {move = mv.limit_length(1.0), jump = bits & 1 != 0, punch = bits & 2 != 0, grab = bits & 4 != 0, dive = bits & 8 != 0}


func _on_roll(lane: int, bowler: int, knocked: int, kind: String) -> void:
	if over or not scores.has(bowler):
		return
	var pts := knocked + (STRIKE_BONUS if kind == "strike" else SPARE_BONUS if kind == "spare" else 0)
	var comeback: bool = _top_score() - scores[bowler].total >= COMEBACK_GAP and pts > 0
	if comeback:
		pts = int(ceil(pts * 1.5))
	scores[bowler].total += pts
	scores[bowler].rolls.append("X" if kind == "strike" else "/" if kind == "spare" else "-" if knocked == 0 else str(knocked))
	_send(_ev_scores, [scores])
	_send(_ev_roll, [lane, bowler, knocked, kind, pts, comeback])


func _on_ko(victim: Beast, by: int) -> void:
	if scores.has(victim.pid):
		scores[victim.pid].streak = 0
	if by == 0 or by == victim.pid or not scores.has(by):
		_send(_ev_feed, ["%s curled up" % victim.display_name, victim.color])
		return
	scores[by].streak += 1
	var who: String = Net.players[by].name if Net.players.has(by) else "?"
	var line := "%s knocked out %s" % [who, victim.display_name]
	if scores[by].streak == 3:
		line += "  — ON A RAMPAGE!"
	_send(_ev_feed, [line, Net.players[by].color if Net.players.has(by) else Color.WHITE])


func _on_flattened(by: int, victim: Beast) -> void:
	if over or not scores.has(by) or by == victim.pid:
		return
	scores[by].total += FLATTEN_POINTS
	_send(_ev_scores, [scores])
	_send(_ev_feed, ["%s bowled over %s  +%d" % [Net.players[by].name, victim.display_name, FLATTEN_POINTS], Color("ffe14d")])


func _end_match() -> void:
	over = true
	_send(_ev_end, [])
	get_tree().create_timer(10.0).timeout.connect(Net.end_match)


func _leader() -> int:
	var best := 0
	var top := 0
	for pid in scores:
		if scores[pid].total > top:
			top = scores[pid].total
			best = pid
	return best


func _top_score() -> int:
	var top := 0
	for pid in scores:
		top = maxi(top, scores[pid].total)
	return top


func _pack_beasts() -> Array:
	var out := []
	for pid in beasts:
		var b: Beast = beasts[pid]
		var flags := int(b.holding != null) | int(b.reaching) << 1 | int(b.leader) << 3
		out.append([pid, b.global_position, b.global_basis.get_rotation_quaternion(), b.state, b.facing,
			b.charge if b.charging else -1.0, b.punch_t[0], b.punch_t[1], flags, b.health, b.immune, b.last_toucher])
	return out


# ================================================================= events (host -> everyone)

func _send(method: Callable, args: Array, local := true) -> void:
	if local:
		method.callv(args)
	for pid in _ready_peers:
		rpc_id.callv([pid, method.get_method()] + args)


@rpc("any_peer", "reliable")
func _hello() -> void:
	var pid := multiplayer.get_remote_sender_id()
	if Net.players.has(pid):
		_ready_peers[pid] = true
		_ev_scores.rpc_id(pid, scores)
		if over:
			_ev_end.rpc_id(pid)


@rpc("authority", "unreliable_ordered")
func _snap(t: float, bs: Array, tl: float) -> void:
	_snaps.append([t, bs, tl])
	if _snaps.size() > 30:
		_snaps.pop_front()


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _snap_pins(t: float, pins: PackedByteArray) -> void:
	_pin_snaps.append([t, pins])
	if _pin_snaps.size() > 30:
		_pin_snaps.pop_front()


@rpc("authority", "call_local", "unreliable")
func _ev_fx(clip: String, pos: Vector3, vol: float) -> void:
	Sfx.play(clip, pos, vol)
	var near := clampf(1.0 - pos.distance_to(cam.global_position) / 30.0, 0.0, 1.0)
	if clip in ["smack", "pins", "ko"]:
		_shake = maxf(_shake, 0.25 * near * (1.5 if clip == "smack" else 1.0))
	match clip:
		"punch": _burst(pos, Color("fff3b0"), 10, 3.0)
		"smack":
			_burst(pos, Color("ffe14d"), 24, 6.0)
			if near > 0.5:
				hud.impact()  # Super Battle Golf-style impact frame on big hits near you
		"pins": _burst(pos + Vector3(0, 0.6, -1.0), Color.WHITE, 30, 5.0)
		"ko": _burst(pos + Vector3.UP * 0.8, Color("ffe14d"), 16, 2.5)


func _burst(pos: Vector3, col: Color, amount: int, speed: float) -> void:
	var p := CPUParticles3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.06
	dot.height = 0.12
	dot.radial_segments = 6
	dot.rings = 3
	p.mesh = dot
	p.material_override = Look.neon(col, 4.0)
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.45
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


@rpc("authority", "call_local", "reliable")
func _ev_feed(text: String, col: Color) -> void:
	hud.feed(text, col)


@rpc("authority", "call_local", "reliable")
func _ev_scores(s: Dictionary) -> void:
	scores = s
	_refresh_boards()


@rpc("authority", "call_local", "reliable")
func _ev_roll(lane: int, bowler: int, knocked: int, kind: String, pts: int, comeback: bool) -> void:
	var who: String = Net.players[bowler].name if Net.players.has(bowler) else "?"
	var col: Color = Net.players[bowler].color if Net.players.has(bowler) else Color.WHITE
	var pos := Vector3(arena.lane_x(lane), 1.0, Arena.HEAD_PIN_Z)
	var extra := "  COMEBACK x1.5" if comeback else ""
	match kind:
		"strike":
			hud.big("STRIKE!", Color("ffe14d"), "%s  +%d%s" % [who, pts, extra])
			arena.screen_board.flash("STRIKE!", Color("ffe14d"))
			Sfx.play_ui("strike")
		"spare":
			hud.big("SPARE!", Color("2de2ff"), "%s  +%d%s" % [who, pts, extra])
			arena.screen_board.flash("SPARE!", Color("2de2ff"))
			Sfx.play_ui("spare")
		"gutter":
			hud.feed("%s threw a gutter ball" % who, col)
			Sfx.play("buzzer", pos, -6.0)
		_:
			hud.feed("%s knocked %d pins  +%d%s" % [who, knocked, pts, extra], col)


@rpc("authority", "call_local", "reliable")
func _ev_end() -> void:
	over = true
	hud.results(_rows())
	Sfx.play_ui("strike")


# ================================================================= presentation

func _process(dt: float) -> void:
	if not server:
		_interpolate(dt)
	var me: Beast = beasts.get(Net.my_id())
	if me:
		hud.set_me(me.health, me.charge / Beast.FULL_CHARGE if me.charging else -1.0, me.state >= Beast.BALL, me.net_holding or me.holding != null)
	hud.set_time(time_left)
	arena.screen_board.time_left = time_left
	arena.screen_board.queue_redraw()
	_update_camera(dt, me)


func _interpolate(dt: float) -> void:
	if _snaps.is_empty():
		return
	_clock += dt
	var target: float = _snaps[-1][0] - INTERP_DELAY
	_clock = target if absf(_clock - target) > 0.25 else lerpf(_clock, target, 0.05)
	var s := _bracket(_snaps)
	var a: Array = s[0]
	var b: Array = s[1]
	var w: float = s[2]
	time_left = b[2]
	if not _pin_snaps.is_empty():
		var p := _bracket(_pin_snaps)
		arena.apply_pins(p[0][1], p[1][1], p[2])
	var prev := {}
	for e in a[1]:
		prev[e[0]] = e
	for e in b[1]:
		var bst: Beast = beasts.get(e[0])
		if bst == null:
			continue
		var pe: Array = prev.get(e[0], e)
		bst.global_transform = Transform3D(Basis(pe[2].slerp(e[2], w)), pe[1].lerp(e[1], w))
		bst.state = e[3]
		bst.facing = e[4]
		bst.charging = e[5] >= 0.0
		bst.charge = maxf(e[5], 0.0)
		bst.punch_t = [e[6], e[7]]
		bst.net_holding = e[8] & 1 != 0
		bst.reaching = e[8] & 2 != 0
		bst.leader = e[8] & 8 != 0
		bst.health = e[9]
		bst.immune = e[10]
		bst.last_toucher = e[11]


func _bracket(buf: Array) -> Array:
	## The two snapshots around the render clock, plus the blend weight. Drops older ones.
	while buf.size() > 2 and buf[1][0] <= _clock:
		buf.pop_front()
	var a: Array = buf[0]
	var b: Array = buf[mini(1, buf.size() - 1)]
	return [a, b, clampf((_clock - a[0]) / maxf(b[0] - a[0], 0.0001), 0.0, 1.0)]


func _update_camera(dt: float, me: Beast) -> void:
	# Follow your own bowl down the lane for a moment, like Super Battle Golf follows the ball.
	if _follow == null and me:
		for b: Beast in beasts.values():
			if b.state == Beast.BALL and b.last_toucher == me.pid and b != me and b.global_position.z < 1.0 \
					and b.global_position.z > -3.0 and arena.lane_at(b.global_position.x) >= 0:
				_follow = b
				_follow_t = 2.6
	if _follow:
		_follow_t -= dt
		if _follow_t <= 0.0 or not is_instance_valid(_follow) or _follow.state != Beast.BALL:
			_follow = null
	var focus := Vector3(0, 0, 4)
	if _follow:
		focus = _follow.global_position
	elif me:
		focus = me.global_position
	# Low and behind, looking down the lanes so you can always see the pins.
	var want := focus + Vector3(0, 6.5, 9.0)
	want.x = clampf(want.x, -Arena.HALF_W + 3.5, Arena.HALF_W - 3.5)  # don't peek outside the alley
	cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-dt * (2.5 if _follow else 5.0)))
	cam.look_at(cam.global_position + Vector3(0, -6.5, -14.0).normalized())
	_shake = maxf(_shake - dt * 1.2, 0.0)
	cam.h_offset = randf_range(-1.0, 1.0) * _shake
	cam.v_offset = randf_range(-1.0, 1.0) * _shake


func _rows() -> Array:
	var rows := []
	for pid in scores:
		if Net.players.has(pid):
			rows.append({name = Net.players[pid].name, color = Net.players[pid].color, total = scores[pid].total, rolls = scores[pid].rolls})
	rows.sort_custom(func(x, y): return x.total > y.total)
	return rows


func _refresh_boards() -> void:
	var rows := _rows()
	hud.board.set_rows(rows, time_left)
	arena.screen_board.set_rows(rows, time_left)
