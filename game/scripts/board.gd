class_name Board
extends Node3D
## The party board, drawn from Net.party on every peer. The world is Party Park (park.gd and its venues); this is
## the game on top of it: everyone's piece, the camera, the screen, and the show, which plays each big moment one at
## a time with its own camera shot (a trophy won, the referee, Trade Deadline, each zone's happening). The host also
## keeps time: the opening tour, bots' rolls, items and decisions, timeouts, the show, and the minigame intro.

const TOUR := 10.0
const ROLL_TIMEOUT := 15.0
const CHOOSE_TIMEOUT := 15.0
const INTRO := 4.5
const FINAL := 25.0  # then the host takes everyone back to the lobby
const MAP_AT := Vector3(0, 175, 85)  # the whole island, from high over the sea
const MAP_LOOK := Vector3(0, 0, -6)
const FOLLOW := Vector3(0, 13.5, 10.0)  # the camera's place behind a piece: steep, so the park doesn't get in the way
const ZONES := {plaza = "the Plaza", courts = "the Courts", golf = "the Golf Course", dojo = "the Sumo Dojo", speedway = "the Speedway",
	mountain = "the Mountain", bowling = "the Bowling Alley", beach = "the Beach", ballpark = "the Ballpark", stadium = "the Stadium"}
const TITLES := {trophy = "TROPHY!", trophy_move = "THE TROPHY MOVES!", ref = "THE REF!", trade = "TRADE DEADLINE!", fore = "FORE!",
	wave = "THE WAVE!", dunk = "SLAM DUNK!", cannon = "T-SHIRT CANNON!", gulls = "SEAGULLS!", homerun = "HOME RUN!",
	pitstop = "PIT STOP!", ski = "SKI JUMP!", avalanche = "AVALANCHE!", duel = "SUMO DUEL!", strike = "STRIKE!", mascot = "MASCOT HEIST!"}
const CALLS := {yellow = ["YELLOW CARD!", "-10 coins"], offside = ["OFFSIDE!", "back 5 spaces"], penalty = ["PENALTY!", "pays 3 coins to everyone"],
	red = ["RED CARD!", "sent back to the start"], cap = ["SALARY CAP!", "everyone's coins are shared out"]}
const DEAL_TEXT := {coins10 = "gives 10 coins to", coins20 = "gives 20 coins to", swap_coins = "swaps coins with",
	trophy = "gives a trophy to", swap_trophies = "swaps trophies with"}
const SHOP_PICK := ["golden", "double", "drink", "swap", "magnet", "whistle"]  # bots' shopping list, best first

var park: Park
var _pieces := {}  # pid -> {root, model, dice, block, path: Array[Vector3], t, events, landed, from}
var _cam: Camera3D
var _cam_at := MAP_AT
var _cam_look := MAP_LOOK
var _want_at := MAP_AT
var _want_look := MAP_LOOK
var _map := false
var _arrows: Array[Node3D] = []
var _trophy_at := -1  # where the trophy is drawn (during the show it lags the state, which has already moved it)
var _phase := ""
var _phase_t := 0.0  # since this phase began, on this screen
var _host_t := 0.0
var _bot_at := {}
var _banked := false
var _autoplay := OS.get_cmdline_user_args().has("--autoplay")  # test hook: this screen's player plays like a bot
var _news_seen := 0
var _show_i := -1
var _show_e := []
var _once := {}  # things the current show entry has already done
var _temp: Array[Node] = []  # the current show's props, freed when it ends
var _ref: BowlerModel
var _mascot: BowlerModel
# the screen
var _ui: Control
var _round: Label
var _sub: Label
var _news: Label
var _title: Label
var _title_sub: Label
var _cards: VBoxContainer
var _roll: Button
var _items: HBoxContainer
var _stop: VBoxContainer
var _stop_title: Label
var _stop_row: HBoxContainer
var _roulette: PanelContainer
var _slots: Array[Label] = []
var _intro: PanelContainer
var _final: PanelContainer
var _map_btn: Button


func _ready() -> void:
	UI.use(false)  # a sunny island: the light palette
	park = Park.new()
	add_child(park)
	_cam = Camera3D.new()
	_cam.fov = 42.0
	_cam.far = 1500.0
	add_child(_cam)
	_cam.current = true
	_ref = Venues.npc(self, Vector3(0, -50, 0), Color("f4f1ea"), {hat = "cap", outfit = "stripes", accent = "black", eyes = "angry", mouth = "mustache"}, 1.25)
	_ref.visible = false
	_mascot = Venues.npc(self, Vector3(0, -50, 0), Color("ff8c2a"), {hat = "party", eyes = "googly", mouth = "grin", outfit = "polka", accent = "yellow"}, 1.6)
	_mascot.visible = false
	if Look.fast():
		Look.no_shadow(self)
	_hud()
	Net.party_changed.connect(_sync)
	Net.players_changed.connect(_sync)
	_sync()
	Music.play("menu")


# ---------------------------------------------------------------- state -> picture

func _sync() -> void:
	var s: Dictionary = Net.party
	if s.is_empty():
		return
	for pid in s.players:
		if Net.players.has(pid) and not _pieces.has(pid):
			_add_piece(pid)
	for pid in _pieces.keys():
		if not Net.players.has(pid):
			_pieces[pid].root.queue_free()
			_pieces.erase(pid)
	if _trophy_at < 0 or s.phase != "show":
		_trophy_at = s.star
	(park.venues.plaza as Venues.Plaza).bank.text = "BANK\n%d" % s.bank
	if s.phase != _phase:
		_enter(s.phase, s)
	if s.phase == "roll":
		for pid in _pieces:  # items like a Swap Ticket move pieces before anyone rolls
			_place(pid, s)
			_pieces[pid].dice.text = str(s.rolls[pid]) if s.rolls.has(pid) else ("??" if s.doubled.has(pid) else "?")
	if _news_seen < s.news_n and not s.news.is_empty():  # the latest happening, across the top for a few seconds
		_news_seen = s.news_n
		var line: Array = s.news[-1]
		if Net.players.has(line[0]):
			_news.text = "%s %s%s" % [_name(line[0]), line[1], (" " + _name(line[2])) if Net.players.has(line[2]) else ""]
			if _phase != "show":
				UI.pop_in(_news)
				_news.modulate.a = 1.0
				_news.create_tween().tween_property(_news, "modulate:a", 0.0, 0.6).set_delay(4.0)
	_refresh_hud(s)


func _name(pid) -> String:
	return Net.players[pid].name if Net.players.has(pid) else "Someone"


func _enter(phase: String, s: Dictionary) -> void:
	if _phase == "show":
		_show_stop()
	_phase = phase
	_phase_t = 0.0
	_host_t = 0.0
	_bot_at.clear()
	_intro.visible = phase == "intro"
	_final.visible = phase == "final"
	_title.visible = false
	_title_sub.visible = false
	var stadium: Venues.Stadium = park.venues.stadium
	match phase:
		"tour":
			_banner("Welcome to Party Park!", "%d rounds of sports, chaos and trophies" % s.rounds)
			stadium.show_text("PARTY PARK", "Let's get this party started!")
		"roll":
			for pid in _pieces:
				_place(pid, s)
				_pieces[pid].dice.visible = true
				_pieces[pid].block.visible = true
			Sfx.play_ui("beep")
			var lead: Array = Party.standings(s).filter(func(pid): return Net.players.has(pid))
			stadium.show_text("ROUND %d" % s.round, ("Leader: " + _name(lead[0])) if not lead.is_empty() else "")
			if Party.frenzy(s):
				_banner("FINAL ROUND FRENZY!", "Blue and red spaces count double")
				stadium.show_text("FINAL ROUND!", "Double coins on every space")
		"move":
			for pid in s.moves:
				if _pieces.has(pid):
					var m: Dictionary = s.moves[pid]
					var p: Dictionary = _pieces[pid]
					p.path = m.path.map(func(i): return i)
					p.times = Party.hop_times(m.from, m.path)
					p.t = 0.0
					p.landed = m.path.is_empty()
					p.from = p.root.position
					p.events = m.events
					p.block.visible = false
					p.dice.visible = not m.path.is_empty()
					p.dice.text = str(m.path.size()) if not m.path.is_empty() else ""
		"show":
			_show_i = -1
			for pid in _pieces:
				_pieces[pid].dice.visible = false
				_pieces[pid].block.visible = false
		"choose":
			for pid in _pieces:
				_place(pid, s)
				_pieces[pid].dice.visible = false
				_pieces[pid].block.visible = false
		"intro":
			var g: Dictionary = Arena.maps()[s.next_game]
			_intro.get_node("V/Name").text = g.name
			_intro.get_node("V/Rules").text = g.rules
			UI.pop_in.call_deferred(_intro)
			Sfx.play_ui("go")
			stadium.show_text(g.name.to_upper(), "Next minigame!")
			for pid in _pieces:
				_place(pid, s)
				_pieces[pid].dice.visible = false
				_pieces[pid].block.visible = false
		"final":
			_ceremony(s)
			_show_final(s)


func _place(pid: int, s: Dictionary) -> void:
	## Pieces sharing a space stand in a little circle.
	var space: int = s.players[pid].space
	var here: Array = s.players.keys().filter(func(o): return s.players[o].space == space and _pieces.has(o))
	var i: int = here.find(pid)
	var r := 0.5 + 0.22 * here.size()
	var off := Vector3.ZERO if here.size() == 1 else Vector3(cos(TAU * i / here.size()), 0, sin(TAU * i / here.size())) * r
	_pieces[pid].root.position = park.spot(space) + off
	_pieces[pid].root.rotation = Vector3.ZERO


func _process(dt: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	_phase_t += dt
	var s: Dictionary = Net.party
	var cup: Node3D = park.trophy.get_node("Cup")
	cup.rotation.y += dt * 1.4
	cup.position.y = 2.2 + sin(t * 2.0) * 0.18
	if _trophy_at >= 0 and not (_phase == "show" and _show_e.size() > 0 and _show_e[0] in ["trophy", "trophy_move"]):
		park.trophy.position = park.spot(_trophy_at)
	for a in _arrows:
		a.position.y = a.get_meta("y") + absf(sin(t * 5.0)) * 0.5
	for pid in _pieces:
		var p: Dictionary = _pieces[pid]
		var moving := _move_piece(pid, p, dt, s)
		p.block.rotation = Vector3(t * 2.3, t * 3.1, 0.0)
		if p.block.visible and not s.is_empty() and _phase == "roll" and not s.rolls.has(pid):
			p.dice.text = str(int(t * 14.0 + pid) % (Party.DICE * (2 if s.doubled.has(pid) else 1)) + 1)  # whirling until you hit it
		var winner: bool = _phase == "final" and not s.is_empty() and Party.standings(s)[0] == pid
		p.model.pose(dt, {speed = 4.0 if moving else 0.0, dance = winner or _phase == "intro" or p.get("cheer", false)})
	if _phase == "show" and not s.is_empty():
		_show_process(s, dt)
	_ref.pose(dt, {})
	_mascot.pose(dt, {dance = true})
	_update_camera(dt, s)
	if Net.is_host():
		_host_clock(dt)
	elif _autoplay and not s.is_empty() and _phase_t > 1.5:
		_autoplay_turn(s)


func _autoplay_turn(s: Dictionary) -> void:
	## --autoplay on a client: roll, use items and decide at stops over the network, as a bot would.
	var me := Net.my_id()
	if s.phase == "roll" and s.players.has(me) and not s.rolls.has(me) and not has_meta("rolled%d" % s.round):
		set_meta("rolled%d" % s.round, true)
		if not s.players[me].items.is_empty():
			Net.party_use(0)
		Net.party_roll()
	elif s.phase == "choose" and s.stops.has(me) and _phase_t > 2.0:
		_phase_t = 0.0  # once per couple of seconds while it's waiting on us
		Net.party_choose(_bot_pick(s, me, true))


func _move_piece(pid: int, p: Dictionary, dt: float, s: Dictionary) -> bool:
	## Hop along the path (riding the chairlift's cable between its stations). Returns whether the piece is on the go.
	if _phase != "move" or p.get("landed", true):
		return false
	p.t += dt
	var k := 0
	while k < p.times.size() and p.t >= p.times[k]:
		k += 1
	if k < p.path.size():
		var to: int = p.path[k]
		var a: Vector3 = p.from if k == 0 else park.spot(p.path[k - 1])
		var b := park.spot(to)
		var start: float = p.times[k - 1] if k > 0 else 0.0
		var f: float = (p.t - start) / (p.times[k] - start)
		var prev: int = p.path[k - 1] if k > 0 else Net.party.moves[pid].from
		if Party.LIFT.has(prev) and Party.LIFT.has(to):  # riding up the cable
			var m: Venues.Mountain = park.venues.mountain
			p.root.position = m.lift_point(smoothstep(0.0, 1.0, f)) + Vector3(0, -0.6, 0)
		else:
			p.root.position = a.lerp(b, f) + Vector3(0, sin(PI * f) * 0.9, 0)
		var dir := b - a
		p.root.rotation.y = atan2(-dir.x, -dir.z)
		p.dice.text = str(p.path.size() - k)
		if p.t - start < dt * 1.5:
			Sfx.play_ui("tick", -8.0)
		return true
	p.landed = true
	p.dice.text = ""
	p.root.position = park.spot(p.path[-1])
	_land(pid, p.events)
	return false


func _land(pid: int, events: Array) -> void:
	var at: Vector3 = _pieces[pid].root.position + Vector3(0, 2.6, 0)
	var delay := 0.0
	for e in events:
		var text := ""
		var col := UI.LIGHT
		match e[0]:
			"broke":
				text = "Need %d coins for the trophy" % Party.STAR_COST
				col = Color("ffb0b0")
			"coins", "booth":
				text = ("The bank pays out! " if e[0] == "booth" else "") + ("%+d" % e[1])
				col = Color("9cc4ff") if e[1] >= 0 else Color("ff8f8f")
				if e[1] > 0:
					_coin_burst(at - Vector3(0, 1.6, 0), mini(e[1], 12))
					Sfx.play_ui("ding", -6.0)
			"item":
				text = "Got a %s!" % Party.ITEMS[e[1]].name
				col = Color("ffd166")
				Sfx.play_ui("spare", -4.0)
		if text != "":
			_popup(at, text, col, delay)
			delay += 0.7


# ---------------------------------------------------------------- the show

func _show_process(s: Dictionary, dt: float) -> void:
	## Which entry of the show is on now (every screen works it out from the same list and clock).
	var acc := 0.0
	for i in s.show.size():
		var d: float = Party.SHOW[s.show[i][0]]
		if _phase_t < acc + d:
			if i != _show_i:
				_show_stop()
				_show_i = i
				_show_e = s.show[i]
				_show_start(_show_e, s)
			_show_tick(_show_e, _phase_t - acc, dt, s)
			return
		acc += d
	_show_stop()


func _show_stop() -> void:
	## The current entry is over: tidy up, and everyone stands where the rules say.
	for n in _temp:
		if is_instance_valid(n):
			n.queue_free()
	_temp.clear()
	_ref.visible = false
	_mascot.visible = false
	_roulette.visible = false
	if not _show_e.is_empty() and _show_e[0] == "trophy_move":
		_trophy_at = _show_e[2]
	for pid in _pieces:
		_pieces[pid].cheer = false
	_show_e = []
	_once.clear()
	var s: Dictionary = Net.party
	if not s.is_empty():
		for pid in _pieces:
			_place(pid, s)


func _piece(pid) -> Node3D:
	return _pieces[pid].root if _pieces.has(pid) else null


func _show_start(e: Array, s: Dictionary) -> void:
	var who := _name(e[1]) if e[0] != "trophy_move" else ""
	var sub := ""
	match e[0]:
		"trophy":
			sub = "%s wins a trophy!" % who
			Sfx.play_ui("strike")
			Sfx.play_ui("cheer", -4.0)
			if _piece(e[1]):
				_burst(_piece(e[1]).position)
		"trophy_move":
			sub = "Next stop: %s" % ZONES[Party.zone(e[2])]
		"ref":
			var call: Array = CALLS[e[2]]
			sub = "%s: %s, %s" % [who, call[0].to_lower().trim_suffix("!"), call[1]]
			Sfx.play_ui("whistle")
			var at := park.spot(e[3])
			_ref.position = at + Vector3(1.6, 1.0, 0.4)
			_ref.rotation.y = PI * 0.4
			_ref.visible = true
			_ref.scale = Vector3.ONE * 0.01
			_ref.create_tween().tween_property(_ref, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			if e[2] in ["yellow", "red"]:
				var card := Look.mesh(self, Venues.box(Vector3(0.6, 0.85, 0.05)), Venues.glow(Color("ffd60a") if e[2] == "yellow" else Color("ef2b2d"), 0.6),
					_ref.position + Vector3(0.3, 1.4, 0))
				card.visible = false
				_temp.append(card)
		"trade":
			sub = "Two players make a deal they didn't ask for!"
			_roulette.visible = true
			UI.pop_in(_roulette)
			Sfx.play_ui("hurry")
		"fore":
			sub = "%s's drive conks %s!" % [who, _name(e[2])]
			(park.venues.golf as Venues.Golf).swing()
			var ball := Look.mesh(self, Venues.ball(0.35), Venues.ball_mat(5), (park.venues.golf as Venues.Golf).tee())
			_temp.append(ball)
		"wave":
			sub = "The crowd showers %s with coins!" % who
			(park.venues.stadium as Venues.Stadium).wave()
			(park.venues.stadium as Venues.Stadium).show_text("WAVE!", "Make some noise!")
			Sfx.play_ui("cheer")
		"dunk":
			sub = "%s slam dunks for %d coins!" % [who, e[2]]
			(park.venues.courts as Venues.Courts).dunk()
		"cannon":
			sub = "%s catches %s!" % [who, ("a " + Party.ITEMS[e[2]].name) if e[2] != "" else "5 coins"]
			if _piece(e[1]):
				(park.venues.plaza as Venues.Plaza).cannon(_piece(e[1]).position)
		"gulls":
			sub = "They took %s's %s!" % [who, Party.ITEMS[e[2]].name if e[2] != "" else "%d coins" % -e[3]]
			if _piece(e[1]):
				(park.venues.beach as Venues.Beach).gulls(_piece(e[1]).position)
		"homerun":
			sub = "%s is knocked clean across the park!" % who
			(park.venues.ballpark as Venues.Ballpark).swing()
			Sfx.play_ui("cheer", -6.0)
		"pitstop":
			sub = "%s hitches a ride in a race car!" % who
		"ski":
			sub = "%s flies off the ski jump!" % who
		"avalanche":
			var names: Array = e[2].map(func(pid): return _name(pid))
			sub = "%s swept down the mountain!" % (", ".join(names) + (" is" if names.size() == 1 else " are"))
			(park.venues.mountain as Venues.Mountain).avalanche(park.spot(e[3][0]), park.spot(Party.BASE))
			Sfx.play_ui("buzzer", -6.0)
		"duel":
			sub = "%s vs %s" % [who, _name(e[2])]
			Sfx.play_ui("smack")
		"strike":
			sub = "%s bowls a strike: +%d coins!" % [who, e[2]]
			Sfx.play_ui("strike")
			if _piece(e[1]):
				var ball := Look.mesh(self, Venues.ball(1.1), Venues.paint(Color("e5383b"), 0.1), _piece(e[1]).position)
				_temp.append(ball)
		"mascot":
			sub = "%s's mascot pinches %s from %s!" % [who, e[3], _name(e[2])]
			if _piece(e[2]):
				_mascot.position = _piece(e[2]).position + Vector3(-1.8, 1.2, 0.5)
				_mascot.visible = true
				_mascot.scale = Vector3.ONE * 0.01
				_mascot.create_tween().tween_property(_mascot, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			Sfx.play_ui("whiff")
	var title: String = TITLES[e[0]]
	if e[0] == "ref":
		title = CALLS[e[2]][0]
	_banner(title, sub)


func _show_tick(e: Array, t: float, _dt: float, s: Dictionary) -> void:
	## One frame of the current entry: move what moves, and point the camera at it.
	var p := _piece(e[1]) if e[0] != "trophy_move" and e[0] != "trade" else null
	var look := p.position if p else park.spot(0)
	var dist := 1.0
	match e[0]:
		"trophy":
			var head := p.position + Vector3(0, 2.4, 0) if p else park.spot(e[2])
			park.trophy.position = park.spot(e[2]).lerp(head - Vector3(0, 2.2, 0), smoothstep(0.0, 1.2, t))
			if p:
				_pieces[e[1]].cheer = true
			dist = 0.6
		"trophy_move":
			var f := smoothstep(0.3, 3.2, t)
			var a := park.spot(e[1])
			var b := park.spot(e[2])
			park.trophy.position = a.lerp(b, f) + Vector3(0, sin(PI * f) * 28.0, 0)
			look = park.trophy.position
			dist = 1.4
		"ref":
			if not _temp.is_empty() and t > 1.1:
				_temp[0].visible = true
			if p and e[3] != e[4] and t > 2.3:
				var f := clampf((t - 2.3) / 2.0, 0.0, 1.0)
				p.position = park.spot(e[3]).lerp(park.spot(e[4]), smoothstep(0.0, 1.0, f)) + Vector3(0, sin(PI * f) * (3.0 + park.spot(e[3]).distance_to(park.spot(e[4])) * 0.25), 0)
				look = p.position
			dist = 0.7
		"trade":
			_spin_roulette(e, t, s)
			var a := _piece(e[2])
			var b := _piece(e[3])
			if a and b:
				look = (a.position + b.position) * 0.5
				dist = clampf(a.position.distance_to(b.position) / 18.0, 1.0, 4.0)
			if t > 4.6 and a:
				_pieces[e[3]].cheer = true
		"fore":
			var golf: Venues.Golf = park.venues.golf
			look = golf.tee()
			if t > 0.8 and not _temp.is_empty() and p:
				var victim := _piece(e[2])
				var to := victim.position + Vector3(0, 1.4, 0) if victim else look
				var f := clampf((t - 0.8) / 2.4, 0.0, 1.0)
				_temp[0].position = golf.tee().lerp(to, f) + Vector3(0, sin(PI * f) * (10.0 + golf.tee().distance_to(to) * 0.35), 0)
				look = _temp[0].position
				dist = 1.2
				if f >= 1.0 and not _temp[0].has_meta("hit"):
					_temp[0].set_meta("hit", true)
					Sfx.play_ui("smack")
					_coin_burst(to, mini(e[3] * 2, 12))
					_popup(to + Vector3(0, 1.2, 0), "BONK! -%d" % e[3], Color("ff8f8f"))
		"wave":
			look = Vector3(0, 0, -2)
			dist = 2.3
			if t > 2.0 and not _flag("coins"):
				for pid in [e[1]] + e[2]:
					if _piece(pid):
						_coin_burst(_piece(pid).position, 8)
		"dunk":
			look = (park.venues.courts as Venues.Courts).hoop()
			dist = 0.9
			if t > 1.4 and p and not _flag("coins"):
				_coin_burst(p.position, mini(e[2], 12))
				_popup(p.position + Vector3(0, 2.4, 0), "+%d" % e[2], Color("9cc4ff"))
		"cannon":
			if p:
				look = p.position.lerp((park.venues.plaza as Venues.Plaza).mascot.position, 0.3)
			dist = 1.0
		"gulls":
			dist = 0.7
			if t > 1.0 and p and not _flag("loot"):
				_popup(p.position + Vector3(0, 2.4, 0), "-%s" % (Party.ITEMS[e[2]].name if e[2] != "" else str(-e[3])), Color("ff8f8f"))
		"homerun":
			if p:
				var f := clampf((t - 0.9) / 3.4, 0.0, 1.0)
				var a := park.spot(e[2])
				var b := park.spot(e[3])
				p.position = a.lerp(b, f) + Vector3(0, sin(PI * f) * (16.0 + a.distance_to(b) * 0.3), 0)
				p.rotation.x = f * TAU * 2.0
				look = p.position
				dist = 1.3
				if f > 0.0 and not _flag("crack"):
					Sfx.play_ui("smack")
		"pitstop":
			if p:
				var sp: Venues.Speedway = park.venues.speedway
				var start := sp.ride(0.25)
				if t < 0.6:
					p.position = park.spot(e[2]).lerp(start.origin, t / 0.6) + Vector3(0, sin(PI * t / 0.6) * 2.0, 0)
				elif t < 3.6:
					var xf := sp.ride(0.25 + (t - 0.6) / 3.0)
					p.position = xf.origin + Vector3(0, 0.3, 0)
					p.basis = xf.basis
				else:
					var f := clampf((t - 3.6) / 1.0, 0.0, 1.0)
					p.basis = Basis()
					p.position = start.origin.lerp(park.spot(e[3]), f) + Vector3(0, sin(PI * f) * 5.0, 0)
				look = p.position
				dist = 1.1
		"ski":
			if p:
				var m: Venues.Mountain = park.venues.mountain
				var len := m.jump.get_baked_length()
				var top := m.jump.sample_baked(0.0)
				var lip := m.jump.sample_baked(len)
				if t < 0.7:
					p.position = park.spot(e[2]).lerp(top, t / 0.7) + Vector3(0, sin(PI * t / 0.7) * 2.0, 0)
				elif t < 2.0:
					var xf := m.jump.sample_baked_with_rotation(len * smoothstep(0.0, 1.0, (t - 0.7) / 1.3) * 0.999, true)
					p.position = xf.origin + Vector3(0, 0.2, 0)
				else:
					var f := clampf((t - 2.0) / 2.4, 0.0, 1.0)
					var b := park.spot(e[3])
					p.position = lip.lerp(b, f) + Vector3(0, sin(PI * f) * 9.0 * (1.0 - f * 0.5), 0)
					p.rotation.x = -0.5 * sin(PI * f)
				look = p.position
				dist = 1.2
		"avalanche":
			look = park.spot(Party.BASE).lerp(park.spot(e[3][0]), 0.5)
			dist = 2.0
			for k in e[2].size():
				var v := _piece(e[2][k])
				if v and t > 1.0:
					var f := clampf((t - 1.0) / 2.6, 0.0, 1.0)
					v.position = park.spot(e[3][k]).lerp(park.spot(Party.BASE), f) + Vector3(0, absf(sin(f * PI * 3.0)) * 1.5, 0)
					v.rotation.x = f * TAU * 2.0
		"duel":
			var o := _piece(e[2])
			if p and o:
				look = (p.position + o.position) * 0.5
				dist = 0.8
				if t > 1.4 and not _flag("dice"):
					_popup(p.position + Vector3(0, 2.6, 0), str(e[3]), Color("ffd166"))
					_popup(o.position + Vector3(0, 2.6, 0), str(e[4]), Color("ffd166"))
				if t > 2.6 and not _flag("result"):
					if e[5] != 0:
						var w := p if e[5] > 0 else o
						_pieces[e[1] if e[5] > 0 else e[2]].cheer = true
						_coin_burst(w.position, 5)
						_popup(w.position + Vector3(0, 3.4, 0), "+%d" % absi(e[5]), Color("9cc4ff"))
					else:
						_popup(look + Vector3(0, 3.0, 0), "A tie!", UI.LIGHT)
		"strike":
			if p and not _temp.is_empty():
				var f := clampf(t / 2.4, 0.0, 1.0)
				var dir := Vector3(1, 0, 0.3).normalized()
				_temp[0].position = p.position - dir * 10.0 + dir * 20.0 * f + Vector3(0, 1.1, 0)
				_temp[0].rotation.z = -f * 20.0
				for pid in e[3]:
					var v := _piece(pid)
					if v and v.position.distance_to(_temp[0].position) < 2.5 and not v.has_meta("struck"):
						v.set_meta("struck", true)
						_popup(v.position + Vector3(0, 2.4, 0), "-3", Color("ff8f8f"))
						Sfx.play("pins", v.position, 0.0)
					if v and v.has_meta("struck"):
						v.position.y += 0.08
						v.rotation.z += 0.12
				if t > 3.5:
					for pid in e[3]:
						if _piece(pid):
							_piece(pid).remove_meta("struck")
				dist = 1.2
		"mascot":
			var v := _piece(e[2])
			if v:
				look = v.position
				dist = 0.7
				if t > 1.6 and not _flag("grab"):
					_popup(v.position + Vector3(0, 2.6, 0), "-" + e[3], Color("ff8f8f"))
					Sfx.play_ui("punch")
	_aim(look, dist)


func _flag(what: String) -> bool:
	## True from the second time this entry asks: things that should happen once.
	if _once.has(what):
		return true
	_once[what] = true
	return false


func _spin_roulette(e: Array, t: float, s: Dictionary) -> void:
	## Trade Deadline's three wheels: who, what, to whom. They stop one by one.
	var names: Array = s.players.keys().filter(func(pid): return Net.players.has(pid)).map(func(pid): return _name(pid))
	if names.is_empty():
		return
	var deals: Array = DEAL_TEXT.values()
	var k := int(t * 12.0)
	_slots[0].text = _name(e[2]) if t > 1.6 else names[k % names.size()]
	_slots[1].text = DEAL_TEXT[e[4]] if t > 2.8 else deals[k % deals.size()]
	_slots[2].text = _name(e[3]) if t > 4.0 else names[(k + 1) % names.size()]
	for i in 3:
		_slots[i].modulate = Color("ffd23f") if t > [1.6, 2.8, 4.0][i] else UI.LIGHT
	if t > 4.0 and not _flag("deal"):
		Sfx.play_ui("strike")


func _aim(look: Vector3, dist: float) -> void:
	_want_look = look + Vector3(0, 0.8, 0)
	_want_at = look + FOLLOW * dist


# ---------------------------------------------------------------- host clock

func _host_clock(dt: float) -> void:
	var s: Dictionary = Net.party
	if s.is_empty():
		return
	_host_t += dt
	match _phase:
		"tour":
			if _host_t > TOUR:
				Party.begin(s)
				Net.push_party()
		"roll":
			var present: Array = s.players.keys().filter(func(pid): return Net.players.has(pid))
			for pid in Party.waiting_on(s, present):
				if Net.players[pid].bot:
					if not _bot_at.has(pid):
						_bot_at[pid] = randf_range(0.8, 2.5)
					if _host_t > _bot_at[pid]:
						for i in range(s.players[pid].items.size() - 1, -1, -1):  # bots use most of what they've got
							if randf() < 0.6:
								Net.party_use_for(pid, i)
						Net.party_roll_for(pid)
				elif _host_t > ROLL_TIMEOUT:
					Net.party_roll_for(pid)  # rolled for you
			if Party.waiting_on(s, present).is_empty() and not present.is_empty():
				Party.resolve(s)
				Net.push_party()
		"move":
			if _host_t > s.move_time:
				Party.after_move(s)
				Net.push_party()
		"show":
			if _host_t > s.show_time + 0.4:
				Party.after_show(s)
				Net.push_party()
		"choose":
			for pid in s.stops.keys():
				var human: bool = Net.players.has(pid) and not Net.players[pid].bot
				if not _bot_at.has(pid):
					_bot_at[pid] = CHOOSE_TIMEOUT if human else randf_range(0.8, 1.6)
				if _host_t > _bot_at[pid] or not Net.players.has(pid):
					Net.party_choose_for(pid, _bot_pick(s, pid, not human))
		"intro":
			if _host_t > INTRO:
				_host_t = -999.0  # once
				Net.map = s.next_game
				Net.start_match(Arena.maps()[s.next_game].seconds)
		"final":
			if _host_t > FINAL:
				_host_t = -999.0
				Net.end_party()


func _bot_pick(s: Dictionary, pid: int, bot: bool):
	## What a bot decides at a stop (and what a human gets if they let the clock run out: the free way, no purchase).
	var stop: Dictionary = s.stops[pid]
	var coins: int = s.players[pid].coins
	match stop.kind:
		"fork":
			var opts: Array = stop.options.filter(func(o): return Party.TOLLS.get(o, 0) <= coins)
			if not bot:
				return opts.filter(func(o): return not Party.TOLLS.has(o)).front() if opts.any(func(o): return not Party.TOLLS.has(o)) else opts[0]
			opts.sort_custom(func(a, b): return Party.steps_to(a, s.star) < Party.steps_to(b, s.star))
			return opts[0] if randf() < 0.7 else opts.pick_random()
		"shop":
			if bot and s.players[pid].items.size() < Party.BAG:
				for k in SHOP_PICK:
					if stop.options.has(k) and coins >= Party.ITEMS[k].price + 8:
						return k
			return "pass"
		_:
			if bot and stop.options.has("trophy") and coins >= Party.MASCOT.trophy:
				return "trophy"
			if bot and stop.options.has("steal") and coins >= 12 and randf() < 0.6:
				return "steal"
			return "pass"


# ---------------------------------------------------------------- the camera

func _update_camera(dt: float, s: Dictionary) -> void:
	## The map if you asked for it; the show's shot; the opening tour; otherwise your own piece (or, watching,
	## whoever's leading).
	var me: Dictionary = _pieces.get(Net.my_id(), {})
	if s.is_empty():
		return
	if _map:
		_want_at = MAP_AT
		_want_look = MAP_LOOK
	elif _phase == "show":
		pass  # the show aims it
	elif _phase == "tour":
		_tour_cam(s)
	elif _phase == "final":
		var plaza := park.on_ground(Vector3(9, 0, 30))
		_want_look = plaza + Vector3(0, 2.5, 0)
		_want_at = plaza + Vector3(0, 7.0, 15.0)
	elif _phase == "intro":
		var sumo: bool = s.next_game.contains("sumo")
		var venue: Vector3 = park.on_ground(Vector3(62, 0, -13) if sumo else Vector3(-52, 0, -24))
		_want_look = venue + Vector3(0, 3, 0)
		_want_at = venue + (Vector3(-14, 12, 16) if sumo else Vector3(20, 11, 8))  # the dojo from the path; the alley's front
	else:
		var focus: Node3D = me.root if not me.is_empty() else null
		if focus == null:
			var lead: Array = Party.standings(s).filter(func(pid): return _pieces.has(pid))
			focus = _pieces[lead[0]].root if not lead.is_empty() else null
		if focus:
			var close: bool = _phase == "choose" or (_phase == "move" and not me.is_empty() and s.moves.has(Net.my_id()))
			_aim(focus.position, 0.9 if close else 1.1)
	var k := 1.0 - exp(-dt * (1.2 if _map or _phase == "tour" else 2.6))
	_cam_at = _cam_at.lerp(_want_at, k)
	_cam_look = _cam_look.lerp(_want_look, k)
	_cam.position = _cam_at
	_cam.look_at(_cam_look)


func _tour_cam(s: Dictionary) -> void:
	## The opening flyover: round the park's sights, then the trophy.
	var stops := [[Vector3(0, 30, 75), Vector3(0, 0, 36)], [Vector3(-14, 34, 26), Vector3(0, 2, -2)], [Vector3(28, 30, -8), Vector3(48, 0, -38)],
		[Vector3(-2, 42, -16), Vector3(-6, 14, -50)], [Vector3(-30, 26, 8), Vector3(-58, 0, -6)]]
	var f := _phase_t / (TOUR - 3.0) * (stops.size() - 1)
	if f < stops.size() - 1:
		var i := int(f)
		var w := smoothstep(0.0, 1.0, f - i)
		_want_at = stops[i][0].lerp(stops[i + 1][0], w)
		_want_look = stops[i][1].lerp(stops[i + 1][1], w)
	else:
		if not has_meta("tour_trophy"):
			set_meta("tour_trophy", true)
			_banner("Find the trophy!", "It's at %s. %d coins buys it" % [ZONES[Party.zone(s.star)], Party.STAR_COST])
			Sfx.play_ui("spare")
		_aim(park.spot(s.star), 1.0)


# ---------------------------------------------------------------- pieces and effects

func _add_piece(pid: int) -> void:
	var info: Dictionary = Net.players[pid]
	var root := Node3D.new()
	add_child(root)
	var model := BowlerModel.new()
	root.add_child(model)
	model.build(info.color, info.skin)
	model.scale = Vector3.ONE * 0.95
	model.position.y = 0.74
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.54
	Look.mesh(root, ring, Look.neon(info.color.lightened(0.2), 1.5), Vector3(0, 0.03, 0)).scale = Vector3(1, 0.3, 1)
	var block := Look.mesh(root, Look.box(Vector3(0.8, 0.8, 0.8)), Look.toy(Color("ffcc33"), 0.2), Vector3(0, 3.0, 0))  # the dice block
	var dice := Label3D.new()
	dice.font = Look.title_font()
	dice.font_size = 110
	dice.outline_size = 26
	dice.outline_modulate = UI.DARK
	dice.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dice.no_depth_test = true
	dice.pixel_size = 0.0072
	dice.position.y = 3.0
	root.add_child(dice)
	_pieces[pid] = {root = root, model = model, dice = dice, block = block, path = []}
	if not Net.party.is_empty():
		_place(pid, Net.party)


func _popup(pos: Vector3, text: String, col: Color, delay := 0.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = Look.title_font()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 80
	l.outline_size = 20
	l.pixel_size = 0.0075
	l.modulate = Color(col, 0.0)
	l.outline_modulate = Color(UI.DARK, 0.0)
	add_child(l)
	l.position = pos
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "modulate:a", 1.0, 0.1).set_delay(delay)
	tw.tween_property(l, "outline_modulate:a", 1.0, 0.1).set_delay(delay)
	tw.tween_property(l, "position", pos + Vector3.UP * 1.4, 1.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(delay)
	tw.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(delay + 1.5)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.4).set_delay(delay + 1.5)
	tw.chain().tween_callback(l.queue_free)


func _coin_burst(at: Vector3, n: int) -> void:
	var p := CPUParticles3D.new()
	p.mesh = Venues.cyl(0.2, 0.2, 0.05, 12)
	p.material_override = Look.neon(Color("ffcc33"), 0.6)
	p.one_shot = true
	p.explosiveness = 0.8
	p.amount = maxi(n, 2)
	p.lifetime = 0.9
	p.direction = Vector3.UP
	p.spread = 30.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 6.0
	p.angular_velocity_min = 360.0
	p.angular_velocity_max = 720.0
	p.position = at + Vector3(0, 1.0, 0)
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


func _burst(at: Vector3) -> void:
	var c := Venues.confetti(self, at + Vector3(0, 3, 0), 3.0)
	c.restart()
	c.emitting = true
	c.finished.connect(c.queue_free)


func _arrows_for(stop: Dictionary) -> void:
	for a in _arrows:
		a.queue_free()
	_arrows.clear()
	if stop.get("kind", "") != "fork":
		return
	for to in stop.options:
		var a := Look.mesh(self, Venues.cyl(0.0, 0.55, 1.0, 12), Look.neon(Color("ffcc33"), 1.2), Vector3.ZERO)
		a.rotation.x = PI  # pointing down at the space
		var at := park.spot(to)
		a.position = at
		a.set_meta("y", at.y + 2.2)
		_arrows.append(a)


func _ceremony(s: Dictionary) -> void:
	## Everyone lines up at the champions' statue, the winner on its plinth.
	var order := Party.standings(s).filter(func(pid): return _pieces.has(pid))
	var plinth := park.on_ground(Vector3(9, 0, 30))
	for i in order.size():
		var root: Node3D = _pieces[order[i]].root
		if i == 0:
			root.position = plinth + Vector3(0, 2.1, 1.0)
		else:
			var side := -1.0 if i % 2 == 1 else 1.0
			root.position = park.on_ground(plinth + Vector3(side * (1.6 + (i - 1) / 2 * 1.4), 0, 2.6)) + Vector3(0, 0.25, 0)
		root.rotation = Vector3.ZERO
		_pieces[order[i]].dice.visible = false
		_pieces[order[i]].block.visible = false
	_burst(plinth + Vector3(0, 2, 0))
	(park.venues.stadium as Venues.Stadium).show_text("CHAMPION!", _name(order[0]) if not order.is_empty() else "")


# ---------------------------------------------------------------- the screen

class Icon extends Control:
	## A tiny trophy or coin, drawn, so it never depends on a font having the glyph.
	var cup := true
	func _init(is_cup: bool) -> void:
		cup = is_cup
		custom_minimum_size = Vector2(24, 24)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
	func _draw() -> void:
		var c := size * 0.5
		if cup:
			var gold := Color("ffb400")
			draw_colored_polygon(PackedVector2Array([c + Vector2(-8, -9), c + Vector2(8, -9), c + Vector2(6, -1), c + Vector2(2, 2),
				c + Vector2(-2, 2), c + Vector2(-6, -1)]), gold)
			draw_rect(Rect2(c + Vector2(-1.5, 2), Vector2(3, 5)), gold)
			draw_rect(Rect2(c + Vector2(-5.5, 7), Vector2(11, 3)), gold)
			draw_arc(c + Vector2(-8, -5), 3.5, PI * 0.5, PI * 1.5, 8, gold, 2.0)
			draw_arc(c + Vector2(8, -5), 3.5, -PI * 0.5, PI * 0.5, 8, gold, 2.0)
		else:
			draw_circle(c, 10.0, Color("e09a00"))
			draw_circle(c, 7.0, Color("ffcc33"))


func _hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = UI.theme()
	layer.add_child(_ui)
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.offset_top = 14
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ui.add_child(top)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -2)
	top.add_child(tv)
	_round = UI.label(tv, "", 40, UI.NAVY, true)
	_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub = UI.label(tv, "", 19, Color(UI.NAVY, 0.7))
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_news = UI.hero(_ui, "", 30)
	_news.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_news.offset_top = 130
	_news.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_news.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title = UI.hero(_ui, "", 76)
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_title.offset_top = 128
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_sub = UI.hero(_ui, "", 30)
	_title_sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_title_sub.offset_top = 222
	_title_sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cards = VBoxContainer.new()
	_cards.position = Vector2(18, 18)
	_cards.add_theme_constant_override("separation", 6)
	_ui.add_child(_cards)
	_roll = UI.primary(UI.button(_ui, "Roll!", func(): Net.party_roll(), 300))
	_roll.add_theme_font_size_override("font_size", 48)
	_roll.custom_minimum_size.y = 88
	_roll.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_roll.offset_left = -340
	_roll.offset_right = -40
	_roll.offset_top = -130
	_roll.offset_bottom = -42
	_items = HBoxContainer.new()  # the item buttons, over Roll
	_items.add_theme_constant_override("separation", 12)
	_items.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_items.offset_top = -220
	_items.offset_bottom = -150
	_items.offset_right = -40
	_items.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ui.add_child(_items)
	_stop = VBoxContainer.new()  # a decision: the ways at a fork, the shop's shelf, the mascot's deals
	_stop.add_theme_constant_override("separation", 10)
	_stop.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_stop.offset_top = -200
	_stop.offset_bottom = -40
	_stop.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stop.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ui.add_child(_stop)
	_stop_title = UI.hero(_stop, "", 34)
	_stop_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stop_row = HBoxContainer.new()
	_stop_row.add_theme_constant_override("separation", 16)
	_stop_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_stop.add_child(_stop_row)
	_map_btn = UI.button(_ui, "Map (M)", func(): _map = not _map, 170)
	_map_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_map_btn.offset_left = -190
	_map_btn.offset_right = -20
	_map_btn.offset_top = 20
	_map_btn.toggle_mode = true
	_roulette = PanelContainer.new()
	_roulette.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_roulette.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_roulette.grow_vertical = Control.GROW_DIRECTION_BOTH
	_roulette.visible = false
	_ui.add_child(_roulette)
	var rh := HBoxContainer.new()
	rh.add_theme_constant_override("separation", 24)
	_roulette.add_child(rh)
	for i in 3:
		var l := UI.label(rh, "", 40, UI.NAVY, true)
		l.custom_minimum_size = Vector2(250, 70)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_slots.append(l)
	_intro = _center_card()
	var iv: VBoxContainer = _intro.get_node("V")
	UI.label(iv, "Next minigame", 24, UI.RED, true)
	var game_name := UI.label(iv, "", 72, UI.NAVY, true)
	game_name.name = "Name"
	var rules := UI.label(iv, "", 24, Color(UI.NAVY, 0.75))
	rules.name = "Rules"
	rules.custom_minimum_size.x = 620
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_final = _center_card()


func _banner(title: String, sub: String) -> void:
	## A big headline across the screen for a few seconds.
	_title.text = title
	_title_sub.text = sub
	_title.visible = true
	_title_sub.visible = sub != ""
	_news.modulate.a = 0.0
	for l in [_title, _title_sub]:
		l.modulate.a = 1.0
		UI.pop_in(l)
		var tw: Tween = l.create_tween()
		tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(3.6)


func _center_card() -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.visible = false
	_ui.add_child(p)
	var v := VBoxContainer.new()
	v.name = "V"
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	return p


func _refresh_hud(s: Dictionary) -> void:
	var me := Net.my_id()
	_round.text = ("Round %d of %d" % [mini(s.round, s.rounds), s.rounds] + ("  ·  Final round!" if Party.frenzy(s) else "")) \
		if s.phase != "final" else "Party over!"
	var present: Array = s.players.keys().filter(func(pid): return Net.players.has(pid))
	match s.phase:
		"tour":
			_sub.text = "Welcome to Party Park!"
		"roll":
			var waiting := Party.waiting_on(s, present).size()
			var last := ""
			if not s.result.is_empty() and Net.players.has(s.result[0][0]):
				last = "%s won %s  ·  " % [_name(s.result[0][0]), Arena.maps()[s.last_game].name]
			_sub.text = last + ("Everyone roll!" if waiting == present.size() else "Waiting on %d..." % waiting)
		"move":
			_sub.text = "Hop hop hop..."
		"show":
			_sub.text = "Meanwhile..."
		"choose":
			_sub.text = "Your call!" if s.stops.has(me) else "Waiting on a decision..."
		"intro":
			_sub.text = "Get ready!"
		_:
			_sub.text = ""
	var can_roll: bool = s.phase == "roll" and s.players.has(me) and not s.rolls.has(me)
	_roll.visible = can_roll
	_roll.text = "Roll two dice!" if s.doubled.has(me) else "Roll!"
	for c in _items.get_children():
		c.queue_free()
	if can_roll:
		var bag: Array = s.players[me].items
		for i in bag.size():
			if (bag[i] == "double" and s.doubled.has(me)) or (bag[i] == "drink" and s.drinks.has(me)):
				continue
			var item: Dictionary = Party.ITEMS[bag[i]]
			var b := UI.button(_items, "Use %s" % item.name, func(): Net.party_use(i), 250)
			b.tooltip_text = UI.sentence(item.hint)
	for c in _stop_row.get_children():
		c.queue_free()
	var stop: Dictionary = s.stops.get(me, {}) if s.phase == "choose" else {}
	_stop.visible = not stop.is_empty()
	_arrows_for(stop)
	if not stop.is_empty():
		var coins: int = s.players[me].coins
		match stop.kind:
			"fork":
				_stop_title.text = "Pick a way!"
				var opts: Array = stop.options.duplicate()
				opts.sort_custom(func(a, b): return Party.pos(a).x < Party.pos(b).x)  # the camera looks north: west is left
				for to in opts:
					var toll: int = Party.TOLLS.get(to, 0)
					var b := UI.primary(UI.button(_stop_row, Party.FORKS[stop.at][to] + (" (%d coins)" % toll if toll > 0 else ""),
						func(): Net.party_choose(to), 320))
					b.disabled = coins < toll
			"shop":
				_stop_title.text = "Pro Shop! Buy something?"
				for k in stop.options:
					if k == "pass":
						UI.button(_stop_row, "No thanks", func(): Net.party_choose("pass"), 200)
						continue
					var item: Dictionary = Party.ITEMS[k]
					var b := UI.primary(UI.button(_stop_row, "%s\n%d coins" % [item.name, item.price], func(): Net.party_choose(k), 230))
					b.tooltip_text = UI.sentence(item.hint)
					b.disabled = coins < item.price or s.players[me].items.size() >= Party.BAG
			"mascot":
				_stop_title.text = "The mascot will do anything for coins..."
				for k in stop.options:
					if k == "pass":
						UI.button(_stop_row, "No thanks", func(): Net.party_choose("pass"), 200)
						continue
					var b := UI.primary(UI.button(_stop_row, ("Pinch 10 coins\nfrom the richest (%d)" if k == "steal" else "Pinch a trophy\nfrom the leader (%d)")
						% Party.MASCOT[k], func(): Net.party_choose(k), 300))
					b.disabled = coins < Party.MASCOT[k]
	for c in _cards.get_children():
		c.queue_free()
	var rank := 0
	for pid in Party.standings(s):
		if not Net.players.has(pid):
			continue
		rank += 1
		var p: Dictionary = s.players[pid]
		var card := PanelContainer.new()
		var style := UI.card(UI.PAPER if pid != me else UI.CREAM, 16, 3)
		style.border_color = Net.players[pid].color
		style.border_width_left = 10
		style.content_margin_top = 6
		style.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", style)
		card.custom_minimum_size.x = 300
		_cards.add_child(card)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", -4)
		card.add_child(col)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		col.add_child(row)
		UI.label(row, str(rank), 22, Color(UI.NAVY, 0.5), true)
		var name := UI.label(row, _name(pid), 22, UI.ink(Net.players[pid].color), true)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(Icon.new(true))
		UI.label(row, str(p.stars), 22, UI.NAVY, true)
		row.add_child(Icon.new(false))
		UI.label(row, str(p.coins), 22, UI.NAVY, true)
		if not p.items.is_empty():
			UI.label(col, "    " + "  ·  ".join(p.items.map(func(k): return Party.ITEMS[k].name)), 15, Color(UI.NAVY, 0.6))


func _unhandled_input(e: InputEvent) -> void:
	if _roll.visible and (e.is_action_pressed("punch") or e.is_action_pressed("jump") or e.is_action_pressed("ui_accept")):
		Net.party_roll()
	if e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_M:
		_map = not _map
		_map_btn.button_pressed = _map
	var s: Dictionary = Net.party
	if not s.is_empty() and s.phase == "choose" and s.stops.has(Net.my_id()) and s.stops[Net.my_id()].kind == "fork" \
			and (e.is_action_pressed("left") or e.is_action_pressed("right")):
		var opts: Array = s.stops[Net.my_id()].options.duplicate()
		opts.sort_custom(func(a, b): return Party.pos(a).x < Party.pos(b).x)
		Net.party_choose(opts[0] if e.is_action_pressed("left") else opts[-1])


func _show_final(s: Dictionary) -> void:
	var v: VBoxContainer = _final.get_node("V")
	for c in v.get_children():
		c.queue_free()
	var order := Party.standings(s).filter(func(pid): return Net.players.has(pid))
	if order.is_empty():
		return
	for b in s.bonus:  # Mario Party's bonus stars, as trophies, already counted in the standings
		var names: Array = b[1].filter(func(pid): return Net.players.has(pid)).map(func(pid): return _name(pid))
		if not names.is_empty():
			UI.label(v, "%s:  %s" % [b[0], ", ".join(names)], 22, UI.TEAL, true)
	UI.label(v, "Party winner!", 30, UI.RED, true)
	UI.label(v, _name(order[0]), 80, UI.NAVY, true)
	var table := GridContainer.new()
	table.columns = 4
	table.add_theme_constant_override("h_separation", 26)
	v.add_child(table)
	for i in order.size():
		var p: Dictionary = s.players[order[i]]
		UI.label(table, str(i + 1), 26, UI.NAVY, true)
		UI.label(table, _name(order[i]), 26, UI.ink(Net.players[order[i]].color), true)
		UI.label(table, "%d trophies" % p.stars if p.stars != 1 else "1 trophy", 24, UI.NAVY, true)
		UI.label(table, "%d coins" % p.coins, 24, Color(UI.NAVY, 0.7))
	if not _banked and not Net.party_mine.is_empty():  # the whole party counts as one match for XP and trophies
		_banked = true
		var row: Dictionary = Net.party_mine.duplicate()
		var prog := Progress.finish_match(row, order[0] == Net.my_id(), row.get("feats", {}))
		Progress.fresh = prog.unlocks
		UI.label(v, "+%d XP" % prog.xp, 26, UI.RED, true)
	if Net.is_host():
		UI.primary(UI.button(v, "Back to the lobby", Net.end_party, 340))
	else:
		UI.label(v, "Back to the lobby soon...", 18, Color(UI.NAVY, 0.6))
	UI.pop_in.call_deferred(_final)
	Music.play("victory", 0.2)
