class_name Bot
## Host-side AI that produces the same input dictionary a human sends. Keeps solo play and tests lively.


static func think(b: Beast, arena: Arena, dt: float) -> Dictionary:
	var own := arena.bot_think(b, dt)  # a minigame with its own way of playing
	return own if not own.is_empty() else _think(b, arena, dt)


static func _think(b: Beast, arena: Arena, dt: float) -> Dictionary:
	var m := b.bot_mem
	var inp := {move = Vector2.ZERO, jump = false, punch = false, grab = false, dive = false}
	m.t = m.get("t", randf()) + dt
	if b.state >= Beast.BALL:
		inp.punch = fmod(m.t, 0.4) < 0.2 and fmod(m.t, 3.0) < 1.5  # mash, with breathers
		return inp
	var pos := b.global_position

	if b.holding is Beast and b.holding.state == Beast.CARRIED:
		inp.grab = true
		return arena.bot_carry(b, m, inp, dt)  # each minigame knows what to do with them
	m.wind = -1.0

	if b.holding != null:  # dragging someone or swinging a pin
		inp.grab = true
		return _fight(b, arena, m, inp, dt, 1.4)

	# Going for a downed player: humans take a beat to notice, don't all go for it, and fumble the grab.
	var ball := _nearest(b, func(o: Beast): return o.state == Beast.BALL and o.held_by == null, 14.0)
	var ball_id := ball.get_instance_id() if ball else 0
	m.reroll = m.get("reroll", 0.0) - dt
	if ball_id != m.get("ball_id", 0) or (m.reroll <= 0.0 and not m.get("wants", false)):
		m.ball_id = ball_id
		var mine := ball != null and ball.ko_by == b.pid  # you knocked them out, you bowl them
		var far := ball != null and ball.global_position.z < -6.0  # a long carry back from the pins rarely pays off
		m.notice = randf_range(0.4, 0.9) if mine else randf_range(0.8, 1.7)
		m.wants = randf() < (0.85 if mine else 0.3) * (0.4 if far else 1.0)
		m.reroll = randf_range(2.0, 3.5)
		m.grab_wait = randf_range(0.3, 0.7)
	m.notice -= dt
	if ball and m.wants and m.notice <= 0.0:
		var to := ball.global_position - pos
		inp.move = Vector2(to.x, to.z).normalized() * (0.8 if to.length() > 2.0 else 0.5)
		if to.length() < 1.5:
			m.grab_wait -= dt
			inp.grab = m.grab_wait <= 0.0
		return inp

	# Item boxes on the back floor: worth a detour when we have nothing and nobody is in our face.
	if b.item == "":
		var box := _nearest_box(b, 12.0)
		if box and (m.get("target") == null or not is_instance_valid(m.target)
				or m.target.global_position.distance_to(pos) > 3.0 or box.global_position.distance_to(pos) < 3.0):
			var to := box.global_position - pos
			inp.move = Vector2(to.x, to.z).normalized()
			return inp
	return _fight(b, arena, m, inp, dt, 1.5)


static func _fight(b: Beast, arena: Arena, m: Dictionary, inp: Dictionary, dt: float, reach: float) -> Dictionary:
	if m.get("retarget", 0.0) <= 0.0 or not is_instance_valid(m.get("target")):
		m.target = _nearest(b, func(o: Beast): return o.state <= Beast.DIVE and o.immune <= 0.0 and not o.out and arena.bot_chases(b, o), 30.0)
		m.retarget = randf_range(0.6, 1.5)
	m.retarget -= dt
	var target = m.target
	if target == null or not is_instance_valid(target):
		var home := arena.bot_home(m.t) - b.global_position
		inp.move = Vector2(home.x, home.z).limit_length(1.0) * 0.6
		return inp
	var to: Vector3 = target.global_position - b.global_position
	var d := Vector2(to.x, to.z).length()
	inp.move = Vector2(to.x, to.z).normalized() * (1.0 if d > reach * 0.8 else 0.25)
	if b.item == "ball" and d > 3.0 and d < 10.0:  # wind up and throw the bowling ball from range
		inp.move *= 0.2
		m.throw = m.get("throw", 0.0) + dt
		inp.punch = m.throw < 0.5
		if m.throw > 0.6:
			m.throw = 0.0
		return inp
	if d > 2.5 and d < 5.0 and randf() < dt * 0.25:
		inp.dive = true
	if randf() < dt * 0.15:
		inp.jump = true
	# Punch rhythm: press, hold (short = jab, long = haymaker), release, rest.
	m.p = m.get("p", 0.0) + dt
	if d < reach + 0.6:
		if m.get("hold", -1.0) < 0.0 and m.p > m.get("rest", 0.3):
			m.hold = 0.05 if randf() < 0.6 else randf_range(0.4, 0.9)
			m.p = 0.0
		if m.get("hold", -1.0) >= 0.0:
			inp.punch = m.p < m.hold
			if not inp.punch:
				m.hold = -1.0
				m.p = 0.0
				m.rest = randf_range(0.15, 0.5)
	return inp


static func _nearest(b: Beast, ok: Callable, max_d: float) -> Beast:
	var best: Beast = null
	for o: Beast in b.get_tree().get_nodes_in_group("beasts"):
		var d := o.global_position.distance_to(b.global_position)
		if o != b and d < max_d and ok.call(o):
			best = o
			max_d = d
	return best


static func _nearest_box(b: Beast, max_d: float) -> Node3D:
	var best: Node3D = null
	for box: Node3D in b.get_tree().get_nodes_in_group("item_boxes"):
		var d := box.global_position.distance_to(b.global_position)
		if box.visible and d < max_d:
			best = box
			max_d = d
	return best

