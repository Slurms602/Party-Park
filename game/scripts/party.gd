class_name Party
## Party mode (Mario Party style): race around the Party Park board, play a sports minigame after every round, earn
## coins, buy stars. Everyone rolls and moves at the same time, so eight players never sit waiting for each other's
## turns; a fork in the path stops you until you pick a way. Pure rules on a plain Dictionary: it syncs as-is
## (Net._party) and tests drive it directly.

## The board, [kind, x, z, next spaces...] (no next: the following space). S start, B blue +3, R red -3, L lucky,
## I item, G seagull (it steals), K ticket booth (a coin bank), and the landmarks' events: D sumo duel, C roller
## coaster, P strike (the bowling alley), W prize wheel. The loop is 0-38; 39-51 the plaza shortcut, 52-61 the lake.
const SPACES := [
	["S", 0.0, 13.0], ["B", 2.7, 13.3], ["K", 5.5, 13.5], ["B", 8.2, 13.2], ["R", 10.9, 12.5],  # 0-4
	["B", 13.3, 11.3], ["I", 15.5, 9.6], ["B", 17.3, 7.4, 8, 39], ["B", 18.5, 5.0], ["L", 19.3, 2.3],  # 5-9
	["D", 19.6, -0.4], ["B", 19.3, -3.1], ["R", 18.6, -5.8], ["B", 17.3, -8.2], ["I", 15.4, -10.2],  # 10-14
	["C", 13.2, -11.8], ["B", 10.7, -12.9], ["G", 8.0, -13.8], ["B", 5.3, -14.3], ["B", 2.6, -14.5],  # 15-19
	["L", -0.2, -14.7], ["R", -2.9, -14.5], ["B", -5.6, -14.0], ["I", -8.3, -13.3], ["B", -10.8, -12.2],  # 20-24
	["B", -13.1, -10.7], ["R", -15.2, -8.8], ["B", -16.8, -6.7], ["B", -18.1, -4.2], ["L", -18.8, -1.5],  # 25-29
	["P", -19.0, 1.2], ["B", -18.5, 3.9, 32, 52], ["R", -17.2, 6.3], ["B", -15.3, 8.4], ["G", -13.2, 10.1],  # 30-34
	["B", -10.8, 11.5], ["R", -8.2, 12.4], ["B", -5.5, 12.8], ["B", -2.8, 12.9, 0], ["R", 14.6, 6.7],  # 35-39
	["B", 12.0, 6.0], ["G", 9.4, 5.2], ["B", 6.7, 4.5], ["W", 4.0, 4.2], ["R", 1.3, 3.9],  # 40-44
	["B", -1.4, 3.5], ["R", -3.9, 2.5], ["L", -6.1, 0.9], ["B", -7.7, -1.3], ["R", -8.7, -3.8],  # 45-49
	["B", -10.1, -6.2], ["I", -11.7, -8.4, 25], ["B", -19.8, 6.3], ["L", -20.8, 8.8], ["B", -20.6, 11.4],  # 50-54
	["I", -19.1, 13.6], ["B", -17.0, 15.3], ["L", -14.5, 16.4], ["B", -11.8, 16.9], ["I", -9.1, 17.0],  # 55-59
	["B", -6.4, 16.5], ["L", -4.1, 15.3, 38],  # 60-61
]
const FORKS := {7: {8: "Sumo Dojo", 39: "Plaza shortcut"}, 31: {32: "Main path", 52: "Lakeside path"}}  # the signposts
const EVENTS := "DCPW"  # the landmark spaces (they count toward the Event Star)
const STAR_SPOTS := [8, 13, 18, 22, 27, 33, 40, 45, 50, 54, 58]
const COASTER_TO := 28  # the roller coaster drops you on the far side of the park
const HOP := 0.3  # seconds per space as pieces hop along (the board animates at this pace)
const START_COINS := 10
const STAR_COST := 20
const DICE := 10
const BLUE := 3
const RED := 3
const LUCKY := [3, 5, 8]
const BOOTH := 3  # passing the ticket booth puts this many coins in; landing on it takes the lot
const BAG := 2  # items you can carry
const ITEMS := {
	double = {name = "Double Dice", hint = "roll two dice this turn", weight = 4},
	swap = {name = "Swap Ticket", hint = "trade places with someone", weight = 3},
	magnet = {name = "Coin Magnet", hint = "take 5 coins from the richest", weight = 3},
	golden = {name = "Golden Ticket", hint = "warp to the star", weight = 1},
}
const WHEEL := ["+10 coins", "+5 coins", "an item", "-5 coins", "a coin swap", "the star moves"]
const PLACE_COINS := [10, 7, 5, 3, 2, 1, 1, 1]  # by finishing place in a minigame


static func new_state(pids: Array, rounds: int) -> Dictionary:
	var players := {}
	for pid in pids:
		players[pid] = _fresh()
	return {round = 1, rounds = rounds, phase = "roll", players = players, rolls = {}, doubled = {}, left = {}, forks = {},
		picks = {}, moves = {}, star = STAR_SPOTS.filter(func(i): return i > 7 and i < 39).pick_random(), bank = 0,
		news = [], news_n = 0, next_game = "", last_game = "", result = [], bonus = []}


static func _fresh() -> Dictionary:
	# mg, most and events count toward the bonus stars at the end
	return {space = 0, coins = START_COINS, stars = 0, items = [], mg = 0, most = START_COINS, events = 0}


static func add_player(state: Dictionary, pid: int) -> void:
	## Late joiners start at the start with the starting coins.
	if not state.players.has(pid):
		state.players[pid] = _fresh()


# ---------------------------------------------------------------- the map

static func kind(i: int) -> String:
	return SPACES[i][0]


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


# ---------------------------------------------------------------- rolling and items

static func roll(state: Dictionary, pid: int) -> int:
	## Returns the number rolled, or 0 if this player can't roll right now.
	if state.phase != "roll" or state.rolls.has(pid) or not state.players.has(pid):
		return 0
	state.rolls[pid] = randi_range(1, DICE) + (randi_range(1, DICE) if state.doubled.has(pid) else 0)
	return state.rolls[pid]


static func waiting_on(state: Dictionary, pids: Array) -> Array:
	return pids.filter(func(pid): return state.players.has(pid) and not state.rolls.has(pid))


static func use_item(state: Dictionary, pid: int, i: int) -> bool:
	## Before you roll. Double Dice counts for this roll; the rest happen right away.
	if state.phase != "roll" or state.rolls.has(pid) or not state.players.has(pid):
		return false
	var p: Dictionary = state.players[pid]
	if i < 0 or i >= p.items.size() or (p.items[i] == "double" and state.doubled.has(pid)):
		return false
	var item: String = p.items.pop_at(i)
	var others: Array = state.players.keys().filter(func(o): return o != pid)
	match item:
		"double":
			state.doubled[pid] = true
			_say(state, pid, "will roll two dice!")
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
			others.sort_custom(func(a, b): return state.players[a].coins > state.players[b].coins)
			var got := -_coins(state, others[0], -5)
			_coins(state, pid, got)
			_say(state, pid, "magnetised %d coins from" % got, others[0])
		"golden":
			p.space = _before(state.star)
			_say(state, pid, "warped to the star!")
	return true


static func _before(i: int) -> int:
	for k in SPACES.size():
		if next_spaces(k).has(i):
			return k
	return 0


# ---------------------------------------------------------------- moving

static func resolve(state: Dictionary) -> void:
	## Everyone has rolled: off they go.
	state.left = state.rolls.duplicate()
	state.rolls = {}
	state.doubled = {}
	walk(state)


static func walk(state: Dictionary) -> void:
	## Move everyone with steps left a space at a time, all together (so whoever reaches the star first gets it), until
	## they run out of steps or reach a fork they haven't picked a way at yet.
	var moves := {}
	var going: Array = state.left.keys()
	going.shuffle()  # a dead heat for the star goes to whoever's luckier
	for pid in going:
		moves[pid] = {from = state.players[pid].space, path = [], events = []}
	state.moves = moves  # landing events can reach other players' moves (a strike, a duel)
	while not going.is_empty():
		for pid in going.duplicate():
			var p: Dictionary = state.players[pid]
			var nx := next_spaces(p.space)
			var to: int = nx[0]
			if nx.size() > 1:
				if not state.picks.has(pid):
					state.forks[pid] = nx
					going.erase(pid)
					continue
				to = state.picks[pid]
				state.picks.erase(pid)
			p.space = to
			moves[pid].path.append(to)
			state.left[pid] -= 1
			if to == state.star:
				_star(state, pid, moves[pid])
			if state.left[pid] > 0:
				if kind(to) == "K":
					state.bank -= _coins(state, pid, -BOOTH)
			else:
				state.left.erase(pid)
				going.erase(pid)
				_land(state, pid, moves[pid])
	var longest := 0
	var warp := 0.0
	for pid in moves:
		longest = maxi(longest, moves[pid].path.size())
		if moves[pid].has("warp"):
			warp = 3.5  # a coaster ride or a big jump
	state.move_time = longest * HOP + 2.4 + warp  # every hop, plus a beat to read what happened
	state.phase = "move"


static func after_move(state: Dictionary) -> void:
	## Host, once the hops have played out: anyone at a fork picks a way, or it's minigame time.
	if state.forks.is_empty():
		pick_minigame(state)
	else:
		state.phase = "choose"


static func choose(state: Dictionary, pid: int, to: int) -> bool:
	if state.phase != "choose" or not state.forks.has(pid) or not state.forks[pid].has(to):
		return false
	state.picks[pid] = to
	state.forks.erase(pid)
	if state.forks.is_empty():
		walk(state)
	return true


static func _star(state: Dictionary, pid: int, m: Dictionary) -> void:
	if state.players[pid].coins < STAR_COST:
		m.events.append(["broke"])  # got there without the coins
		return
	_coins(state, pid, -STAR_COST)
	state.players[pid].stars += 1
	m.events.append(["star"])
	_say(state, pid, "got a star!")
	_move_star(state)


static func _move_star(state: Dictionary) -> void:
	var here := pos(state.star)
	state.star = STAR_SPOTS.filter(func(i): return pos(i).distance_to(here) > 12.0).pick_random()


static func _land(state: Dictionary, pid: int, m: Dictionary) -> void:
	var p: Dictionary = state.players[pid]
	var k := kind(p.space)
	if EVENTS.contains(k):
		p.events += 1
	match k:
		"B", "S":
			m.events.append(["coins", _coins(state, pid, BLUE)])
		"R":
			m.events.append(["coins", _coins(state, pid, -RED)])
		"L":
			if randf() < 0.4 and p.items.size() < BAG:
				m.events.append(["item", _give(p)])
			else:
				m.events.append(["lucky", _coins(state, pid, LUCKY.pick_random())])
		"I":
			m.events.append(["item", _give(p)] if p.items.size() < BAG else ["coins", _coins(state, pid, BLUE)])
		"G":  # a seagull swoops down for your snacks
			if not p.items.is_empty() and randf() < 0.5:
				m.events.append(["gull_item", p.items.pop_back()])
			else:
				m.events.append(["gull", _coins(state, pid, -randi_range(5, 10))])
		"K":
			m.events.append(["booth", _coins(state, pid, state.bank)])
			state.bank = 0
		"C":
			p.space = COASTER_TO
			m.warp = COASTER_TO
			m.events.append(["coaster"])
			_say(state, pid, "rode the roller coaster!")
		"P":  # everyone near the alley gets bowled over and drops coins
			var total := 0
			for o in state.players:
				if o != pid and pos(state.players[o].space).distance_to(pos(p.space)) < 7.0:
					var lost := _coins(state, o, -3)
					total -= lost
					if state.moves.has(o):
						state.moves[o].events.append(["struck", lost])
			m.events.append(["strike", _coins(state, pid, total)])
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
			m.events.append(["duel", o, mine, theirs, won])
			if state.moves.has(o):
				state.moves[o].events.append(["dueled", pid, theirs, mine, -won])
			_say(state, pid, "won a sumo duel against" if won > 0 else ("lost a sumo duel to" if won < 0 else "tied a sumo duel with"), o)
		"W":
			var spin: String = WHEEL.pick_random()
			match spin:
				"+10 coins": _coins(state, pid, 10)
				"+5 coins": _coins(state, pid, 5)
				"-5 coins": _coins(state, pid, -5)
				"an item":
					if p.items.size() < BAG:
						_give(p)
					else:
						spin = "+5 coins"
						_coins(state, pid, 5)
				"a coin swap":
					var o: int = state.players.keys().filter(func(x): return x != pid).pick_random() if state.players.size() > 1 else pid
					var c: int = p.coins
					_coins(state, pid, state.players[o].coins - c)
					_coins(state, o, c - state.players[o].coins)
				"the star moves":
					_move_star(state)
			m.events.append(["wheel", spin])
			_say(state, pid, "spun the prize wheel: " + spin)


static func _coins(state: Dictionary, pid: int, n: int) -> int:
	## Give (or take, never below zero) coins. Returns the change.
	var p: Dictionary = state.players[pid]
	var d := maxi(n, -p.coins)
	p.coins += d
	p.most = maxi(p.most, p.coins)
	return d


static func _give(p: Dictionary) -> String:
	var total := 0.0
	for k in ITEMS:
		total += ITEMS[k].weight
	var r := randf() * total
	for k in ITEMS:
		r -= ITEMS[k].weight
		if r <= 0.0:
			p.items.append(k)
			return k
	p.items.append("double")
	return "double"


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


static func _bonus(state: Dictionary) -> void:
	## Mario Party's bonus stars: the most minigame coins, the most coins at once, the most event spaces. Ties all get one.
	state.bonus = []
	for b in [["Minigame Star", "mg"], ["Rich Star", "most"], ["Event Star", "events"]]:
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
	## pids, best first: most stars, then most coins.
	var pids: Array = state.players.keys()
	pids.sort_custom(func(a, b):
		var pa: Dictionary = state.players[a]
		var pb: Dictionary = state.players[b]
		return pa.stars > pb.stars or (pa.stars == pb.stars and pa.coins > pb.coins))
	return pids
