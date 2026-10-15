class_name Party
## Party mode (Mario Party style): race around Party Park, a sports park, play a minigame after every round, earn
## coins, buy trophies. Everyone rolls and moves at the same time, so eight players never sit waiting for each other's
## turns; a fork, a shop or the mascot stops you until you decide. Pure rules on a plain Dictionary: it syncs as-is
## (Net._party) and tests drive it directly. The board (board.gd + park.gd) only draws it.

## The map: the legs of the main loop, in order, then the branches off it. A leg is [id, zone, kinds, control points];
## its spaces are spread evenly along a smooth curve through the points, one per letter of `kinds`:
## S start, B blue +3, R red -3, I item, K ticket booth (a coin bank), H happening (what happens depends on the zone),
## F the referee, T Trade Deadline, $ pro shop, M the mascot, D sumo duel, P strike (the bowling alley), C ski jump.
const LOOP := [
	["plaza", "plaza", "SBK$", [Vector2(0, 41.4), Vector2(8.1, 42.3), Vector2(16.2, 41.4)]],
	["courts", "courts", "BRBHIB", [Vector2(16.2, 41.4), Vector2(24.3, 39.6), Vector2(31.5, 35.1), Vector2(36.9, 28.8)]],
	["golf", "golf", "BBIBRBBFBRBIB", [Vector2(36.9, 28.8), Vector2(44.1, 27.1), Vector2(52.2, 26.2), Vector2(59.5, 20.8),
		Vector2(62.2, 11.7), Vector2(61.3, 2.7), Vector2(55.8, -4.5)]],
	["dojo", "dojo", "BDRB", [Vector2(55.8, -4.5), Vector2(52.2, -10.8), Vector2(46.8, -15.3)]],
	["speedway", "speedway", "BHBRTBRB", [Vector2(46.8, -15.3), Vector2(37.8, -18.0), Vector2(28.8, -18.9), Vector2(21.6, -21.6),
		Vector2(17.1, -27.0)]],
	["trail", "mountain", "BBRBHBIRBFBB$", [Vector2(17.1, -27.0), Vector2(16.2, -34.0), Vector2(9.0, -37.8), Vector2(2.7, -36.9),
		Vector2(-1.8, -41.4), Vector2(4.5, -45.9), Vector2(-2.7, -50.0), Vector2(-10.8, -50.4)]],
	["descent", "mountain", "CBRBIBHRB", [Vector2(-10.8, -50.4), Vector2(-19.8, -48.6), Vector2(-27.9, -43.2), Vector2(-33.3, -36.0),
		Vector2(-36.0, -27.9)]],
	["bowling", "bowling", "BRPBIB", [Vector2(-36.0, -27.9), Vector2(-39.6, -19.8), Vector2(-45.0, -12.6), Vector2(-51.3, -8.1)]],
	["beach", "beach", "BRBIBFBRB", [Vector2(-51.3, -8.1), Vector2(-55.8, 0.0), Vector2(-57.6, 9.0), Vector2(-55.8, 18.0),
		Vector2(-52.2, 25.2)]],
	["ballpark", "ballpark", "BHBMBRB", [Vector2(-52.2, 25.2), Vector2(-46.8, 32.4), Vector2(-38.7, 37.8), Vector2(-29.7, 41.4)]],
	["plazaw", "plaza", "BRBIBHBB", [Vector2(-29.7, 41.4), Vector2(-20.7, 43.2), Vector2(-10.8, 43.2), Vector2(0, 41.4)]],
]
## [id, zone, kinds, from [leg, i], to [leg, i], [name of the main way, name of this way], toll, control points between
## (or, one per space, the spaces themselves)]
const BRANCHES := [
	["stadium", "stadium", "BBRBMBHBIBRBBHBFBRB", ["plaza", 1], ["trail", 0], ["Main street", "Stadium tunnel"], 8,
		[Vector2(2.7, 34.2), Vector2(0.9, 25.2), Vector2(0, 16.2), Vector2(0, 7.2), Vector2(0, -1.8), Vector2(0, -10.8),
		Vector2(1.8, -19.8), Vector2(7.2, -25.2)]],
	["fairway", "golf", "BHRBIBHRB", ["golf", 0], ["dojo", 0], ["Cart path", "Fairway"], 0,
		[Vector2(42.3, 19.8), Vector2(48.6, 11.7), Vector2(52.2, 3.6)]],
	["lift", "mountain", "BB", ["trail", 0], ["descent", 0], ["Hiking trail", "Chairlift"], 3,
		[Vector2(22.0, -31.0), Vector2(-5.5, -55.5)]],  # one space per point: the stations at each end of the cable
	["shore", "beach", "BIBHTBIBRBHB", ["beach", 0], ["ballpark", 0], ["Boardwalk", "Shoreline"], 0,
		[Vector2(-61.2, -5.4), Vector2(-66.6, 3.6), Vector2(-67.5, 14.4), Vector2(-61.2, 23.4)]],
]
const TROPHY_SPOTS := [["courts", 2], ["golf", 5], ["golf", 10], ["fairway", 3], ["speedway", 5], ["trail", 5], ["descent", 3],
	["bowling", 3], ["beach", 2], ["shore", 7], ["ballpark", 4], ["plazaw", 2], ["stadium", 9], ["stadium", 16], ["trail", 1]]
const EVENTS := "HTDPC"  # the spaces that count toward the Hustle Trophy
const STOPS := "$M"  # passing these stops you to decide
const HOP := 0.32  # seconds per space as pieces hop along (the board animates at this pace)
const LIFT_RIDE := 2.6  # seconds up the chairlift's cable
const START_COINS := 10
const STAR_COST := 20  # a trophy
const DICE := 10
const BLUE := 3
const RED := 3
const DRINK := 3
const BOOTH := 3  # passing the ticket booth puts this many coins in; landing on it takes the lot
const BAG := 3  # items you can carry
const MASCOT := {steal = 5, trophy = 30}  # what the mascot charges
const ITEMS := {
	double = {name = "Double Dice", hint = "roll two dice this turn", weight = 4, price = 5},
	drink = {name = "Energy Drink", hint = "+3 to your roll", weight = 4, price = 3},
	swap = {name = "Swap Ticket", hint = "trade places with someone", weight = 3, price = 8},
	magnet = {name = "Coin Magnet", hint = "take 5 coins from the richest", weight = 3, price = 6},
	whistle = {name = "Ref's Whistle", hint = "the ref books the leader: -10 coins", weight = 2, price = 10},
	golden = {name = "Golden Ticket", hint = "warp next to the trophy", weight = 1, price = 20},
}
const REF := {yellow = 3, offside = 2, penalty = 2, red = 1, cap = 1}  # the referee's calls, by weight
const DEALS := {coins10 = 3, coins20 = 2, swap_coins = 2, trophy = 1, swap_trophies = 1}  # Trade Deadline, by weight
## How long each event takes to play out on the board, so the host and every screen agree.
const SHOW := {trophy = 4.5, trophy_move = 3.5, ref = 5.0, trade = 6.5, fore = 4.5, wave = 4.5, dunk = 3.5, cannon = 3.5,
	gulls = 3.5, homerun = 5.0, pitstop = 5.0, ski = 5.0, avalanche = 5.0, duel = 4.5, strike = 4.0, mascot = 4.5}
const PLACE_COINS := [10, 7, 5, 3, 2, 1, 1, 1]  # by finishing place in a minigame
const FRENZY_BONUS := 10  # the last round: last place gets this, and blue and red spaces count double

static var SPACES := []  # [kind, x, z, next spaces...] (no next: the following space)
static var ZONE := []  # the zone each space is in
static var LEG := {}  # leg id -> index of its first space
static var FORKS := {}  # fork space -> {next space: name of that way}
static var TOLLS := {}  # first space of a toll way -> coins
static var STAR_SPOTS := []
static var LIFT := []  # the chairlift's spaces (the board flies pieces along its cable)
static var SKI_TO := 0  # the ski jump lands you here
static var BASE := 0  # the foot of the mountain: avalanches end here


static func _static_init() -> void:
	## Lay the spaces along the legs and branches.
	var loop_n := 0
	for leg in LOOP:
		LEG[leg[0]] = loop_n
		loop_n += leg[2].length()
	for k in LOOP.size():
		var leg: Array = LOOP[k]
		var n: int = leg[2].length()
		var at := _spread(leg[3], n, false, LOOP[k - 1][3][-2], LOOP[(k + 1) % LOOP.size()][3][1])
		for i in n:
			SPACES.append([leg[2][i], snappedf(at[i].x, 0.01), snappedf(at[i].y, 0.01)])
			ZONE.append(leg[1])
	SPACES[loop_n - 1].append(0)  # round the loop
	for b in BRANCHES:
		var first := SPACES.size()
		LEG[b[0]] = first
		var from: int = LEG[b[3][0]] + b[3][1]
		var to: int = LEG[b[4][0]] + b[4][1]
		var n: int = b[2].length()
		var at: Array = b[7] if b[7].size() == n else _spread([_xz(from)] + b[7] + [_xz(to)], n, true)
		for i in n:
			SPACES.append([b[2][i], snappedf(at[i].x, 0.01), snappedf(at[i].y, 0.01)])
			ZONE.append(b[1])
		SPACES[-1].append(to)
		SPACES[from].append_array([from + 1, first])
		FORKS[from] = {from + 1: b[5][0], first: b[5][1]}
		if b[6] > 0:
			TOLLS[first] = b[6]
		if b[0] == "lift":
			LIFT = range(first, first + n)
	for s in TROPHY_SPOTS:
		STAR_SPOTS.append(LEG[s[0]] + s[1])
	SKI_TO = LEG.bowling + 1
	BASE = LEG.trail


static func _xz(i: int) -> Vector2:
	return Vector2(SPACES[i][1], SPACES[i][2])


static func _spread(pts: Array, n: int, inner: bool, ghost_a = null, ghost_b = null) -> Array:
	## n points evenly along a Catmull-Rom curve through pts: from its start (a loop leg: the next leg starts at its
	## end, and the ghosts are the neighbouring legs' points so the curve runs on smoothly), or strictly between its
	## ends (a branch joins two spaces that are already there).
	var line := []
	for k in pts.size() - 1:
		var p0: Vector2 = pts[k - 1] if k > 0 else (ghost_a if ghost_a != null else pts[0])
		var p1: Vector2 = pts[k]
		var p2: Vector2 = pts[k + 1]
		var p3: Vector2 = pts[k + 2] if k + 2 < pts.size() else (ghost_b if ghost_b != null else pts[-1])
		for s in 24:
			var t := s / 24.0
			line.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	line.append(pts[-1])
	var lens := [0.0]
	for k in range(1, line.size()):
		lens.append(lens[-1] + line[k].distance_to(line[k - 1]))
	var out := []
	var j := 0
	for i in n:
		var want: float = lens[-1] * ((i + 1.0) / (n + 1.0) if inner else float(i) / n)
		while j < line.size() - 2 and lens[j + 1] < want:
			j += 1
		out.append(line[j].lerp(line[j + 1], (want - lens[j]) / maxf(lens[j + 1] - lens[j], 0.0001)))
	return out


static func new_state(pids: Array, rounds: int) -> Dictionary:
	var players := {}
	for pid in pids:
		players[pid] = _fresh()
	var s := {round = 1, rounds = rounds, phase = "tour", players = players, rolls = {}, doubled = {}, drinks = {}, left = {},
		stops = {}, picks = {}, moves = {}, show = [], show_time = 0.0, move_time = 0.0, star = 0, bank = 0, news = [],
		news_n = 0, next_game = "", last_game = "", result = [], bonus = []}
	var near := STAR_SPOTS.filter(func(i): return steps_to(0, i) >= 8 and steps_to(0, i) <= 20)
	s.star = near.pick_random()
	return s


static func _fresh() -> Dictionary:
	# mg, most and events count toward the bonus trophies at the end
	return {space = 0, coins = START_COINS, stars = 0, items = [], mg = 0, most = START_COINS, events = 0}


static func add_player(state: Dictionary, pid: int) -> void:
	## Late joiners start at the start with the starting coins.
	if not state.players.has(pid):
		state.players[pid] = _fresh()


static func begin(state: Dictionary) -> void:
	## The opening tour of the park is over: everyone roll.
	if state.phase == "tour":
		state.phase = "roll"


# ---------------------------------------------------------------- the map

static func kind(i: int) -> String:
	return SPACES[i][0]


static func zone(i: int) -> String:
	return ZONE[i]


static func pos(i: int) -> Vector3:
	return Vector3(SPACES[i][1], 0.0, SPACES[i][2])


static func next_spaces(i: int) -> Array:
	return SPACES[i].slice(3) if SPACES[i].size() > 3 else [i + 1]


static func steps_to(from: int, to: int) -> int:
	## Fewest hops from one space to another (forks take whichever way is shorter).
	var seen := {from: 0}
	var queue := [from]
	while not queue.is_empty():
		var i: int = queue.pop_front()
		if i == to:
			return seen[i]
		for n in next_spaces(i):
			if not seen.has(n):
				seen[n] = seen[i] + 1
				queue.append(n)
	return 999


static func ahead(i: int, n: int) -> int:
	## n spaces on along the main way.
	for k in n:
		i = next_spaces(i)[0]
	return i


static func before(i: int) -> int:
	for k in SPACES.size():
		if next_spaces(k).has(i):
			return k
	return 0


static func frenzy(state: Dictionary) -> bool:
	return state.round >= state.rounds and state.rounds > 1


# ---------------------------------------------------------------- rolling and items

static func roll(state: Dictionary, pid: int) -> int:
	## Returns the number rolled, or 0 if this player can't roll right now.
	if state.phase != "roll" or state.rolls.has(pid) or not state.players.has(pid):
		return 0
	state.rolls[pid] = randi_range(1, DICE) + (randi_range(1, DICE) if state.doubled.has(pid) else 0) \
		+ (DRINK if state.drinks.has(pid) else 0)
	return state.rolls[pid]


static func waiting_on(state: Dictionary, pids: Array) -> Array:
	return pids.filter(func(pid): return state.players.has(pid) and not state.rolls.has(pid))


static func use_item(state: Dictionary, pid: int, i: int) -> bool:
	## Before you roll. Dice items count for this roll; the rest happen right away.
	if state.phase != "roll" or state.rolls.has(pid) or not state.players.has(pid):
		return false
	var p: Dictionary = state.players[pid]
	if i < 0 or i >= p.items.size() or (p.items[i] == "double" and state.doubled.has(pid)) or (p.items[i] == "drink" and state.drinks.has(pid)):
		return false
	var item: String = p.items.pop_at(i)
	var others: Array = state.players.keys().filter(func(o): return o != pid)
	match item:
		"double":
			state.doubled[pid] = true
			_say(state, pid, "will roll two dice!")
		"drink":
			state.drinks[pid] = true
			_say(state, pid, "downed an Energy Drink: +3!")
		"swap":
			if others.is_empty():
				return true
			var o: int = others.pick_random()
			var mine: int = p.space
			p.space = state.players[o].space
			state.players[o].space = mine
			_say(state, pid, "used a Swap Ticket on", o)
		"magnet":
			if others.is_empty():
				return true
			var o: int = _richest(state, others)
			var got := -_coins(state, o, -5)
			_coins(state, pid, got)
			_say(state, pid, "magnetised %d coins from" % got, o)
		"whistle":
			if others.is_empty():
				return true
			var o: int = standings(state).filter(func(x): return x != pid)[0]
			_coins(state, o, -10)
			_say(state, pid, "blew the Ref's Whistle on", o)
		"golden":
			p.space = before(state.star)
			_say(state, pid, "warped to the trophy!")
	return true


static func _richest(state: Dictionary, pids: Array) -> int:
	var best: int = pids[0]
	for o in pids:
		if state.players[o].coins > state.players[best].coins:
			best = o
	return best


# ---------------------------------------------------------------- moving

static func resolve(state: Dictionary) -> void:
	## Everyone has rolled: off they go.
	state.left = state.rolls.duplicate()
	state.rolls = {}
	state.doubled = {}
	state.drinks = {}
	walk(state)


static func walk(state: Dictionary) -> void:
	## Move everyone with steps left a space at a time, all together (so whoever reaches the trophy first gets it),
	## until they run out of steps or reach a fork, a shop or the mascot. Landings happen once everyone has stopped,
	## so an event that moves other players never catches them mid-walk.
	var moves := {}
	var going: Array = state.left.keys()
	going.shuffle()  # a dead heat for the trophy goes to whoever's luckier
	for pid in going:
		moves[pid] = {from = state.players[pid].space, path = [], events = []}
	state.moves = moves  # landing events can reach other players' moves (a strike, a duel)
	var landed := []
	while not going.is_empty():
		for pid in going.duplicate():
			var p: Dictionary = state.players[pid]
			var nx := next_spaces(p.space)
			var to: int = nx[0]
			if nx.size() > 1:
				if not state.picks.has(pid):
					state.stops[pid] = {kind = "fork", at = p.space, options = nx}
					going.erase(pid)
					continue
				to = state.picks[pid]
				state.picks.erase(pid)
			p.space = to
			moves[pid].path.append(to)
			state.left[pid] -= 1
			if to == state.star:
				_star(state, pid, moves[pid])
			if STOPS.contains(kind(to)):
				state.stops[pid] = _stop(state, pid, to)
				going.erase(pid)
				if state.left[pid] <= 0:
					state.left.erase(pid)  # landed right on it: that's all this space does
				continue
			if state.left[pid] > 0:
				if kind(to) == "K":
					state.bank -= _coins(state, pid, -BOOTH)
			else:
				state.left.erase(pid)
				going.erase(pid)
				landed.append(pid)
	for pid in landed:
		_land(state, pid, moves[pid])
	var longest := 0.0
	for pid in moves:
		var times := hop_times(moves[pid].from, moves[pid].path)
		longest = maxf(longest, times[-1] if not times.is_empty() else 0.0)
	state.move_time = longest + 1.6  # every hop, plus a beat to read what happened
	state.phase = "move"


static func hop_times(from: int, path: Array) -> Array:
	## When each hop of a move ends, in seconds from the start (a ride up the chairlift takes longer).
	var out := []
	var t := 0.0
	var prev := from
	for i in path:
		t += LIFT_RIDE if LIFT.has(prev) and LIFT.has(i) else HOP
		out.append(t)
		prev = i
	return out


static func after_move(state: Dictionary) -> void:
	## Host, once the hops have played out: the big moments, then whoever has a decision to make, then a minigame.
	if not state.show.is_empty():
		state.phase = "show"
		state.show_time = 0.0
		for e in state.show:
			state.show_time += SHOW[e[0]]
	elif state.stops.is_empty():
		pick_minigame(state)
	else:
		state.phase = "choose"


static func after_show(state: Dictionary) -> void:
	state.show = []
	after_move(state)


static func choose(state: Dictionary, pid: int, option) -> bool:
	## A way at a fork, an item at a shop (or "pass"), or a deal with the mascot.
	if state.phase != "choose" or not state.stops.has(pid) or not state.stops[pid].options.has(option):
		return false
	var p: Dictionary = state.players[pid]
	var stop: Dictionary = state.stops[pid]
	match stop.kind:
		"fork":
			var toll: int = TOLLS.get(option, 0)
			if p.coins < toll:
				return false
			_coins(state, pid, -toll)
			state.picks[pid] = option
			if toll > 0:
				_say(state, pid, "paid %d coins for the %s" % [toll, FORKS[stop.at][option]])
		"shop":
			if option != "pass":
				var item: Dictionary = ITEMS[option]
				if p.coins < item.price or p.items.size() >= BAG:
					return false
				_coins(state, pid, -item.price)
				p.items.append(option)
				_say(state, pid, "bought a %s" % item.name)
		"mascot":
			if option != "pass" and p.coins < MASCOT[option]:
				return false
			if option != "pass":
				_mascot(state, pid, option)
	state.stops.erase(pid)
	if state.stops.is_empty():
		walk(state)
	return true


static func _stop(state: Dictionary, pid: int, at: int) -> Dictionary:
	var p: Dictionary = state.players[pid]
	if kind(at) == "$":
		var stock := ITEMS.keys()
		stock.shuffle()
		return {kind = "shop", at = at, options = stock.slice(0, 3) + ["pass"]}
	var opts := []
	var others: Array = state.players.keys().filter(func(o): return o != pid)
	if not others.is_empty():
		opts.append("steal")
		if others.any(func(o): return state.players[o].stars > 0):
			opts.append("trophy")
	return {kind = "mascot", at = at, options = opts + ["pass"]}


static func _mascot(state: Dictionary, pid: int, deal: String) -> void:
	## The mascot works for whoever pays: it pinches coins from the richest, or a trophy from whoever has the most.
	var others: Array = state.players.keys().filter(func(o): return o != pid)
	_coins(state, pid, -MASCOT[deal])
	if deal == "steal":
		var o: int = _richest(state, others)
		var got := -_coins(state, o, -10)
		_coins(state, pid, got)
		state.show.append(["mascot", pid, o, "%d coins" % got])
		_say(state, pid, "sent the mascot to pinch %d coins from" % got, o)
	else:
		others.sort_custom(func(a, b): return state.players[a].stars > state.players[b].stars)
		if state.players[others[0]].stars <= 0:  # someone lost it since the mascot offered
			_coins(state, pid, MASCOT[deal])
			return
		state.players[others[0]].stars -= 1
		state.players[pid].stars += 1
		state.show.append(["mascot", pid, others[0], "a trophy"])
		_say(state, pid, "sent the mascot to pinch a trophy from", others[0])


static func _star(state: Dictionary, pid: int, m: Dictionary) -> void:
	if state.players[pid].coins < STAR_COST:
		m.events.append(["broke"])  # got there without the coins
		return
	_coins(state, pid, -STAR_COST)
	state.players[pid].stars += 1
	state.show.append(["trophy", pid, state.star])
	_say(state, pid, "won a trophy!")
	_move_star(state)


static func _move_star(state: Dictionary) -> void:
	## Somewhere well away, but where someone could reach it in a few rounds.
	var here := pos(state.star)
	var spots := STAR_SPOTS.filter(func(i): return pos(i).distance_to(here) > 25.0)
	var near := spots.filter(func(i):
		var best := 999
		for pid in state.players:
			best = mini(best, steps_to(state.players[pid].space, i))
		return best >= 6 and best <= 30)
	var to: int = (near if not near.is_empty() else spots).pick_random()
	state.show.append(["trophy_move", state.star, to])
	state.star = to


static func _moved(state: Dictionary, pid: int) -> void:
	## An event picked this player up: whatever they were in the middle of is off.
	state.stops.erase(pid)
	state.left.erase(pid)
	state.picks.erase(pid)


static func _land(state: Dictionary, pid: int, m: Dictionary) -> void:
	var p: Dictionary = state.players[pid]
	var k := kind(p.space)
	var x := 2 if frenzy(state) else 1
	if EVENTS.contains(k):
		p.events += 1
	match k:
		"B", "S":
			m.events.append(["coins", _coins(state, pid, BLUE * x)])
		"R":
			m.events.append(["coins", _coins(state, pid, -RED * x)])
		"I":
			m.events.append(["item", _give(p)] if p.items.size() < BAG else ["coins", _coins(state, pid, BLUE)])
		"K":
			m.events.append(["booth", _coins(state, pid, state.bank)])
			state.bank = 0
		"H":
			_happening(state, pid, m)
		"F":
			_referee(state, pid)
		"T":
			_trade(state, pid)
		"C":
			var from: int = p.space
			p.space = SKI_TO
			state.show.append(["ski", pid, from, SKI_TO])
			_say(state, pid, "took the ski jump!")
		"P":  # everyone near the alley gets bowled over and drops coins
			var total := 0
			var hit := []
			for o in state.players:
				if o != pid and pos(state.players[o].space).distance_to(pos(p.space)) < 9.0:
					var lost := _coins(state, o, -3)
					total -= lost
					hit.append(o)
			state.show.append(["strike", pid, _coins(state, pid, total), hit])
			_say(state, pid, "bowled a strike!")
		"D":  # a sumo duel with whoever is closest: higher roll takes 5 coins
			var foes: Array = state.players.keys().filter(func(o): return o != pid)
			if foes.is_empty():
				m.events.append(["coins", _coins(state, pid, BLUE)])
				return
			foes.sort_custom(func(a, b): return pos(state.players[a].space).distance_to(pos(p.space)) < pos(state.players[b].space).distance_to(pos(p.space)))
			var o: int = foes[0]
			var mine := randi_range(1, DICE)
			var theirs := randi_range(1, DICE)
			var won := 0
			if mine != theirs:
				var winner: int = pid if mine > theirs else o
				won = -_coins(state, o if winner == pid else pid, -5)
				_coins(state, winner, won)
				won *= 1 if winner == pid else -1
			state.show.append(["duel", pid, o, mine, theirs, won])
			_say(state, pid, "won a sumo duel against" if won > 0 else ("lost a sumo duel to" if won < 0 else "tied a sumo duel with"), o)


static func _happening(state: Dictionary, pid: int, m: Dictionary) -> void:
	## Each part of the park has its own surprise.
	var p: Dictionary = state.players[pid]
	var others: Array = state.players.keys().filter(func(o): return o != pid)
	match zone(p.space):
		"plaza":  # the mascot's T-shirt cannon fires you a prize
			var what: String = _give(p) if p.items.size() < BAG else ""
			if what == "":
				_coins(state, pid, 5)
			state.show.append(["cannon", pid, what])
			_say(state, pid, "caught a prize from the T-shirt cannon!")
		"courts":
			var n := _coins(state, pid, randi_range(5, 10))
			state.show.append(["dunk", pid, n])
			_say(state, pid, "slam dunked for %d coins!" % n)
		"golf":  # a stray drive conks someone, and you pocket what they drop
			if others.is_empty():
				m.events.append(["coins", _coins(state, pid, 5)])
				return
			var o: int = others.pick_random()
			var n := -_coins(state, o, -5)
			_coins(state, pid, n)
			state.show.append(["fore", pid, o, n])
			_say(state, pid, "yelled FORE! and conked", o)
		"speedway":  # a lift in a race car
			var from: int = p.space
			p.space = ahead(from, 6)
			state.show.append(["pitstop", pid, from, p.space])
			_say(state, pid, "hitched a ride in a race car!")
		"mountain":  # everyone else on the mountain is swept back down (or you are, if you're alone up there)
			var swept: Array = others.filter(func(o): return zone(state.players[o].space) == "mountain" and state.players[o].space != BASE)
			if swept.is_empty():
				swept = [pid]
			var froms := []
			for o in swept:
				froms.append(state.players[o].space)
				state.players[o].space = BASE
				_moved(state, o)
			state.show.append(["avalanche", pid, swept, froms])
			_say(state, pid, "set off an avalanche!")
		"beach":  # seagulls go for your snacks
			if not p.items.is_empty() and randf() < 0.5:
				state.show.append(["gulls", pid, p.items.pop_back(), 0])
			else:
				state.show.append(["gulls", pid, "", _coins(state, pid, -randi_range(5, 10))])
			_say(state, pid, "was mobbed by seagulls!")
		"ballpark":  # knocked out of the park, to anywhere at all
			var from: int = p.space
			var blues := range(SPACES.size()).filter(func(i): return kind(i) == "B" and i != from)
			p.space = blues.pick_random()
			state.show.append(["homerun", pid, from, p.space])
			_say(state, pid, "was hit for a home run!")
		"stadium":  # the crowd does the wave and showers the stadium with coins
			var fans: Array = others.filter(func(o): return zone(state.players[o].space) == "stadium")
			_coins(state, pid, 8)
			for o in fans:
				_coins(state, o, 4)
			state.show.append(["wave", pid, fans])
			_say(state, pid, "started a Mexican wave!")
		_:
			m.events.append(["coins", _coins(state, pid, 5)])


static func _referee(state: Dictionary, pid: int) -> void:
	## Mario Party's Bowser, in stripes: the ref always finds something to blow the whistle at.
	var p: Dictionary = state.players[pid]
	var call: String = _weighted(REF)
	var from: int = p.space
	match call:
		"yellow":
			_coins(state, pid, -10)
		"offside":
			for k in 5:
				p.space = before(p.space)
		"penalty":  # pay everyone else
			for o in state.players:
				if o != pid:
					_coins(state, o, -_coins(state, pid, -3))
		"red":
			_coins(state, pid, -5)
			p.space = 0
		"cap":  # a salary cap: everyone's coins are shared out evenly
			var total := 0
			for o in state.players:
				total += state.players[o].coins
			for o in state.players:
				state.players[o].coins = floori(float(total) / state.players.size())
	state.show.append(["ref", pid, call, from, p.space])
	_say(state, pid, {yellow = "got a yellow card", offside = "was flagged offside", penalty = "gave away a penalty",
		red = "was sent off with a red card", cap = "triggered the salary cap"}[call] + "!")


static func _trade(state: Dictionary, pid: int) -> void:
	## Trade Deadline (Mario Party's Chance Time): two players, picked at random, make a deal they didn't ask for.
	var pids: Array = state.players.keys()
	if pids.size() < 2:
		_coins(state, pid, 5)
		return
	pids.shuffle()
	var a: int = pids[0]
	var b: int = pids[1]
	var pa: Dictionary = state.players[a]
	var pb: Dictionary = state.players[b]
	var deal: String = _weighted(DEALS)
	if deal == "trophy" and pa.stars == 0:
		deal = "coins20"
	if deal == "swap_trophies" and pa.stars == pb.stars:
		deal = "swap_coins"
	match deal:
		"coins10", "coins20":
			_coins(state, b, -_coins(state, a, -(10 if deal == "coins10" else 20)))
		"swap_coins":
			var c: int = pa.coins
			pa.coins = pb.coins
			pb.coins = c
			pa.most = maxi(pa.most, pa.coins)
			pb.most = maxi(pb.most, pb.coins)
		"trophy":
			pa.stars -= 1
			pb.stars += 1
		"swap_trophies":
			var t: int = pa.stars
			pa.stars = pb.stars
			pb.stars = t
	state.show.append(["trade", pid, a, b, deal])
	_say(state, pid, "called a Trade Deadline!")


static func _weighted(table: Dictionary) -> String:
	var total := 0.0
	for k in table:
		total += table[k]
	var r := randf() * total
	for k in table:
		r -= table[k]
		if r <= 0.0:
			return k
	return table.keys()[0]


static func _coins(state: Dictionary, pid: int, n: int) -> int:
	## Give (or take, never below zero) coins. Returns the change.
	var p: Dictionary = state.players[pid]
	var d := maxi(n, -p.coins)
	p.coins += d
	p.most = maxi(p.most, p.coins)
	return d


static func _give(p: Dictionary) -> String:
	var weights := {}
	for k in ITEMS:
		weights[k] = ITEMS[k].weight
	var item := _weighted(weights)
	p.items.append(item)
	return item


static func _say(state: Dictionary, pid: int, what: String, other := 0) -> void:
	## A line for everyone's board: [pid, what, other pid or 0]. The board puts the names in.
	state.news.append([pid, what, other])
	state.news_n += 1
	if state.news.size() > 6:
		state.news.pop_front()


# ---------------------------------------------------------------- minigames and the end

static func pick_minigame(state: Dictionary) -> String:
	var pool := Arena.maps().keys().filter(func(g): return g != state.last_game)
	state.next_game = pool.pick_random()
	state.last_game = state.next_game
	state.phase = "intro"
	return state.next_game


static func award(state: Dictionary, points: Dictionary) -> void:
	## points: pid -> score in the minigame. Ties share a place (and its coins).
	var result := []
	for pid in points:
		if not state.players.has(pid):
			continue
		var place := points.values().filter(func(v): return v > points[pid]).size()
		var won: int = PLACE_COINS[mini(place, PLACE_COINS.size() - 1)]
		_coins(state, pid, won)
		state.players[pid].mg += won
		result.append([pid, place, won])
	result.sort_custom(func(a, b): return a[1] < b[1])
	state.result = result
	state.round += 1
	state.phase = "final" if state.round > state.rounds else "roll"
	if state.phase == "final":
		_bonus(state)
	elif frenzy(state):  # the final round: a leg-up for whoever's last
		var last: int = standings(state)[-1]
		_coins(state, last, FRENZY_BONUS)
		_say(state, last, "gets %d coins to catch up for the final round!" % FRENZY_BONUS)


static func _bonus(state: Dictionary) -> void:
	## Mario Party's bonus stars, as trophies: the most minigame coins, the most coins at once, the most event spaces.
	## Ties all get one.
	state.bonus = []
	for b in [["Minigame MVP", "mg"], ["Moneybags", "most"], ["Hustle Award", "events"]]:
		var best := 0
		for pid in state.players:
			best = maxi(best, state.players[pid][b[1]])
		if best <= 0:
			continue
		var who: Array = state.players.keys().filter(func(pid): return state.players[pid][b[1]] == best)
		for pid in who:
			state.players[pid].stars += 1
		state.bonus.append([b[0], who])


static func standings(state: Dictionary) -> Array:
	## pids, best first: most trophies, then most coins.
	var pids: Array = state.players.keys()
	pids.sort_custom(func(a, b):
		var pa: Dictionary = state.players[a]
		var pb: Dictionary = state.players[b]
		return pa.stars > pb.stars or (pa.stars == pb.stars and pa.coins > pb.coins))
	return pids
