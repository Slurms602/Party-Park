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
const PRE_GAME := 3.0  # 3, 2, 1, BOWL! (Super Battle Golf's tee-off countdown)
const HURRY_AT := 30.0  # switch to the hurry version of the music

var arena: Arena
var hud: Hud
var cam: Camera3D
var beasts := {}  # pid -> Beast
var inputs := {}  # pid -> latest input (host)
var scores := {}  # pid -> {total, rolls, streak, strikes, spares, kos}
var time_left := 180.0
var pre := PRE_GAME
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
var _dinged := false
var _ready_peers := {}  # host: clients whose Game node exists, so RPCs to it can land
var _pre_shown := -1
var _hurried := false
var _match_t := 0.0


func _ready() -> void:
	server = Net.is_host()
	time_left = Net.match_seconds
	arena = Arena.make(Net.map)
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
	if OS.has_feature("mobile") or "--touch" in OS.get_cmdline_user_args():
		var tc := TouchControls.new()
		tc.me_id = Net.my_id()
		add_child(tc)
	Music.duck(PRE_GAME)
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
			if pid == Net.my_id():
				b.mark_local()
			if server:
				b.knocked_out.connect(_on_ko)
				b.flattened.connect(_on_flattened)
				b.fx.connect(func(clip, pos, vol): _send(_ev_fx, [clip, pos, vol]))
				b.hurt.connect(func(v, by, dir, power, label): _send(_ev_hit, [v.pid, by, dir, power, label]))
		if not scores.has(pid):
			scores[pid] = {total = 0, rolls = [], streak = 0, strikes = 0, spares = 0, kos = 0}
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
	pre = maxf(pre - dt, 0.0)
	for pid in beasts:
		var b: Beast = beasts[pid]
		var inp: Dictionary = Bot.think(b, arena, dt) if Net.players[pid].bot else inputs.get(pid, {})
		b.sim(inp if pre <= 0.0 else {}, dt)  # everyone waits for the countdown
	arena.server_update(dt, beasts.values())
	if not over and pre <= 0.0:
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
		_send(_snap, [_server_time, _pack_beasts(), time_left, pre], false)
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
	var pts := 0 if kind == "foul" else knocked + (STRIKE_BONUS if kind == "strike" else SPARE_BONUS if kind == "spare" else 0)
	var comeback: bool = _top_score() - scores[bowler].total >= COMEBACK_GAP and pts > 0
	if comeback:
		pts = int(ceil(pts * 1.5))
	scores[bowler].total += pts
	scores[bowler].rolls.append({strike = "X", spare = "/", foul = "F"}.get(kind, "-" if knocked == 0 else str(knocked)))
	if kind == "strike":
		scores[bowler].strikes += 1
	elif kind == "spare":
		scores[bowler].spares += 1
	_send(_ev_scores, [scores])
	_send(_ev_roll, [lane, bowler, knocked, kind, pts, comeback])


func _on_ko(victim: Beast, by: int) -> void:
	if scores.has(victim.pid):
		scores[victim.pid].streak = 0
	if by == 0 or by == victim.pid or not scores.has(by) or not Net.players.has(by):
		_send(_ev_feed, [victim.display_name, victim.color, "CURLED UP", Color("6a5a8a"), "", Color.WHITE])
		return
	scores[by].streak += 1
	scores[by].kos += 1
	var rampage: bool = scores[by].streak >= 3
	_send(_ev_feed, [Net.players[by].name, Net.players[by].color, "RAMPAGE KO" if rampage else "KO", Color("ff3b4e") if not rampage else Color("ff8c2a"),
		victim.display_name, victim.color])


func _on_flattened(by: int, victim: Beast) -> void:
	if over or not scores.has(by) or by == victim.pid:
		return
	scores[by].total += FLATTEN_POINTS
	_send(_ev_scores, [scores])
	_send(_ev_feed, [Net.players[by].name, Net.players[by].color, "BOWLED OVER +%d" % FLATTEN_POINTS, Color("c79a00"), victim.display_name, victim.color])


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
		var flags := int(b.holding != null) | int(b.reaching) << 1 | int(b.holding is Beast and b.holding.state == Beast.CARRIED) << 2 | int(b.leader) << 3
		out.append([pid, b.global_position, b.global_basis.get_rotation_quaternion(), b.state, b.facing,
			b.charge if b.charging else -1.0, b.punch_t[0], b.punch_t[1], flags, b.health, b.immune, b.last_toucher, b.ko_time])
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
func _snap(t: float, bs: Array, tl: float, p: float) -> void:
	_snaps.append([t, bs, tl, p])
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


@rpc("authority", "call_local", "unreliable")
func _ev_hit(victim: int, by: int, dir: Vector3, power: float, label: String) -> void:
	var v: Beast = beasts.get(victim)
	var a: Beast = beasts.get(by)
	if v:
		v.react(dir, power)
	if a:
		a.react(dir, power, true)
	if v and label != "":
		_popup(v.global_position + Vector3.UP * 1.8, label, a.color.lightened(0.3) if a else Color.WHITE)
	if victim == Net.my_id() or by == Net.my_id():  # hits you're part of shake harder
		_shake = maxf(_shake, 0.1 + 0.2 * power)
		if power > 0.6:
			hud.impact()


func _popup(pos: Vector3, text: String, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 80
	l.outline_size = 20
	l.pixel_size = 0.006
	l.modulate = col
	l.outline_modulate = Color(0.06, 0.02, 0.12)
	add_child(l)
	l.global_position = pos
	l.scale = Vector3.ONE * 0.4
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "global_position", pos + Vector3.UP * 0.9, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.45)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.3).set_delay(0.45)
	tw.chain().tween_callback(l.queue_free)


@rpc("authority", "call_local", "reliable")
func _ev_feed(a: String, a_col: Color, verb: String, verb_col: Color, b: String, b_col: Color) -> void:
	hud.feed_event(a, a_col, verb, verb_col, b, b_col)


@rpc("authority", "call_local", "reliable")
func _ev_scores(s: Dictionary) -> void:
	scores = s
	_refresh_boards()


@rpc("authority", "call_local", "reliable")
func _ev_roll(lane: int, bowler: int, knocked: int, kind: String, pts: int, comeback: bool) -> void:
	var who: String = Net.players[bowler].name if Net.players.has(bowler) else "?"
	var col: Color = Net.players[bowler].color if Net.players.has(bowler) else Color.WHITE
	var pos := Vector3(arena.lane_x(lane), 1.0, arena.head_pin_z)
	var extra := "  ·  COMEBACK x1.5" if comeback else ""
	match kind:
		"strike":
			hud.callout("STRIKE!", Color("ffe14d"), "%s  +%d%s" % [who, pts, extra], true)
			arena.screen_board.flash("STRIKE!", Color("ffe14d"))
			Music.duck(1.4)
			Sfx.play_ui("strike")
		"spare":
			hud.callout("SPARE!", Color("2de2ff"), "%s  +%d%s" % [who, pts, extra])
			arena.screen_board.flash("SPARE!", Color("2de2ff"))
			Music.duck(1.0)
			Sfx.play_ui("spare")
		"foul":
			hud.callout("FOUL!", Color("ff3b4e"), "%s bowled from past the line: no points" % who)
			arena.screen_board.flash("FOUL!", Color("ff3b4e"))
			arena.flash_foul()
			Sfx.play_ui("foul")
		"gutter":
			hud.feed_event(who, col, "GUTTER BALL", Color("6a5a8a"))
			Sfx.play("buzzer", pos, -6.0)
		_:
			hud.feed_event(who, col, "%d PINS  +%d" % [knocked, pts], Color("2a7fff"), extra.strip_edges().trim_prefix("·  "), Color.WHITE)


@rpc("authority", "call_local", "reliable")
func _ev_end() -> void:
	over = true
	var rows := _rows()
	var top: int = rows[0].pid if not rows.is_empty() else 0
	var p: Dictionary = Net.players.get(top, {color = Color.WHITE, skin = {}})
	hud.results(rows, p.color, p.skin)
	Music.play("victory", 0.2)


# ================================================================= presentation

func _process(dt: float) -> void:
	if not server:
		_interpolate(dt)
	var me: Beast = beasts.get(Net.my_id())
	_match_flow(dt)
	if me:
		var full := me.charging and me.charge >= Beast.FULL_CHARGE - 0.01
		if full and not _dinged:
			Sfx.play_ui("ding", -4.0)  # fully charged
		_dinged = full
		hud.set_me(me.display_name, me.color, me.health, me.state >= Beast.BALL, maxf(me.ko_time, 0.0))
		hud.set_charge(cam.unproject_position(me.global_position + Vector3.UP * 1.9), me.charge / Beast.FULL_CHARGE if me.charging else -1.0)
		hud.set_prompts(_touchify(_prompts(me)))
	hud.set_time(time_left if pre <= 0.0 else Net.match_seconds)
	arena.screen_board.time_left = time_left
	arena.screen_board.queue_redraw()
	_update_camera(dt, me)


func _match_flow(dt: float) -> void:
	## Countdown, hurry-up and music cues, run on every peer from the replicated clock.
	var p := int(ceil(pre))
	if p != _pre_shown:
		if p > 0:
			hud.countdown(str(p), Color.WHITE)
			Sfx.play_ui("beep")
		elif _pre_shown > 0:
			hud.countdown("BOWL!", Color("ffe14d"), 180)
			Sfx.play_ui("go")
			Music.play("match", 0.3)
		_pre_shown = p
	if pre <= 0.0 and not over:
		_match_t += dt
		if _pre_shown == 0 and Music.current == "menu":  # joined mid-match
			Music.play("match", 0.5)
		if time_left <= HURRY_AT and not _hurried:
			_hurried = true
			hud.banner("HURRY UP!", Color("ff5a6a"))
			Sfx.play_ui("hurry")
			Music.play("hurry", 0.8)


func _prompts(me: Beast) -> Array:
	## Context button prompts for the local player.
	if pre > 0.0 or over:
		return []
	if me.state >= Beast.BALL:
		return [["MASH", "ANY BUTTON TO WAKE UP"]]
	if me.net_carrying or (me.holding is Beast and me.holding.state == Beast.CARRIED):
		var out := [["HOLD LMB", "WIND UP"], ["RELEASE", "BOWL!"]]
		if me.global_position.z < 0.3:
			out.append(["!", "GET BEHIND THE FOUL LINE", true])
		return out
	for b: Beast in beasts.values():
		if b != me and b.state == Beast.BALL and b.global_position.distance_to(me.global_position) < 2.8:
			return [["HOLD RMB", "GRAB THEM"]]
	if _match_t < 15.0:
		return [["LMB", "PUNCH"], ["HOLD LMB", "HAYMAKER"], ["RMB", "GRAB"], ["SHIFT", "DIVE"]]
	return []


func _touchify(items: Array) -> Array:
	## Same prompts, phrased for the on-screen buttons.
	if not (OS.has_feature("mobile") or "--touch" in OS.get_cmdline_user_args()):
		return items
	var names := {"LMB": "PUNCH", "HOLD LMB": "HOLD PUNCH", "RMB": "TAP GRAB", "HOLD RMB": "TAP GRAB", "SHIFT": "DIVE", "RELEASE": "LET GO"}
	return items.map(func(it): return [names.get(it[0], it[0])] + it.slice(1))


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
	pre = b[3]
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
		bst.net_carrying = e[8] & 4 != 0
		bst.leader = e[8] & 8 != 0
		bst.health = e[9]
		bst.immune = e[10]
		bst.last_toucher = e[11]
		bst.ko_time = e[12]


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
	want.x = clampf(want.x, -arena.half_w + 3.5, arena.half_w - 3.5)  # don't peek outside the alley
	cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-dt * (2.5 if _follow else 5.0)))
	cam.look_at(cam.global_position + arena.cam_look.normalized())
	_shake = maxf(_shake - dt * 1.2, 0.0)
	cam.h_offset = randf_range(-1.0, 1.0) * _shake
	cam.v_offset = randf_range(-1.0, 1.0) * _shake


func _rows() -> Array:
	var rows := []
	for pid in scores:
		if Net.players.has(pid):
			var sc: Dictionary = scores[pid]
			rows.append({pid = pid, name = Net.players[pid].name, color = Net.players[pid].color, total = sc.total, rolls = sc.rolls,
				me = pid == Net.my_id(), strikes = sc.get("strikes", 0), spares = sc.get("spares", 0), kos = sc.get("kos", 0)})
	rows.sort_custom(func(x, y): return x.total > y.total)
	return rows


func _refresh_boards() -> void:
	var rows := _rows()
	hud.board.set_rows(rows, time_left)
	arena.screen_board.set_rows(rows, time_left)
