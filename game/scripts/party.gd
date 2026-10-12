class_name Party
## Party mode (Mario Party style): race around a board, play a sports minigame after every round, earn coins, buy stars.
## Everyone rolls and moves at the same time, so eight players never sit waiting for each other's turns.
## Pure rules on a plain Dictionary: it syncs as-is (Net._party) and tests drive it directly.

const SPACES := 24
const LAYOUT := "SBBRBLBBRBBLBRBBBLBRBBLR"  # S start, B blue +3, R red -3, L lucky; the star sits on one of them
const START_COINS := 10
const STAR_COST := 20
const DICE := 10
const BLUE := 3
const RED := 3
const LUCKY := [3, 5, 8]
const PLACE_COINS := [10, 7, 5, 3, 2, 1, 1, 1]  # by finishing place in a minigame


static func new_state(pids: Array, rounds: int) -> Dictionary:
	var players := {}
	for pid in pids:
		players[pid] = {space = 0, coins = START_COINS, stars = 0}
	return {round = 1, rounds = rounds, phase = "roll", players = players, rolls = {}, moves = {}, star = 9,
		next_game = "", last_game = "", result = []}


static func add_player(state: Dictionary, pid: int) -> void:
	## Late joiners start at the start with the starting coins.
	if not state.players.has(pid):
		state.players[pid] = {space = 0, coins = START_COINS, stars = 0}


static func roll(state: Dictionary, pid: int) -> int:
	## Returns the number rolled, or 0 if this player can't roll right now.
	if state.phase != "roll" or state.rolls.has(pid) or not state.players.has(pid):
		return 0
	state.rolls[pid] = randi_range(1, DICE)
	return state.rolls[pid]


static func waiting_on(state: Dictionary, pids: Array) -> Array:
	return pids.filter(func(pid): return state.players.has(pid) and not state.rolls.has(pid))


static func resolve(state: Dictionary) -> void:
	## Move everyone at once. Whoever passes the star first (fewest steps) and can pay buys it; then it moves on.
	var moves := {}
	var passers := []
	for pid in state.rolls:
		var p: Dictionary = state.players[pid]
		var n: int = state.rolls[pid]
		var to_star: int = (state.star - p.space + SPACES) % SPACES
		if to_star == 0:
			to_star = SPACES  # standing on it doesn't count; you have to come round again
		if to_star <= n:
			passers.append([to_star, pid])
		moves[pid] = {from = p.space, steps = n, events = []}
	passers.sort()
	var bought := false
	for pass_ in passers:
		var pid: int = pass_[1]
		var p: Dictionary = state.players[pid]
		if not bought and p.coins >= STAR_COST:
			p.coins -= STAR_COST
			p.stars += 1
			bought = true
			moves[pid].events.append(["star", pass_[0]])
		elif not bought:
			moves[pid].events.append(["broke", pass_[0]])  # got there without the coins
	if bought:
		state.star = (state.star + randi_range(9, 15)) % SPACES
		if state.star == 0:
			state.star = 1  # never on the start space
	var longest := 0
	for pid in moves:
		var m: Dictionary = moves[pid]
		var p: Dictionary = state.players[pid]
		p.space = (m.from + m.steps) % SPACES
		longest = maxi(longest, m.steps)
		match LAYOUT[p.space]:
			"B", "S":
				p.coins += BLUE
				m.events.append(["blue", BLUE])
			"R":
				var lost := mini(RED, p.coins)
				p.coins -= lost
				m.events.append(["red", -lost])
			"L":
				var won: int = LUCKY.pick_random()
				p.coins += won
				m.events.append(["lucky", won])
	state.moves = moves
	state.rolls = {}
	state.phase = "move"
	state.move_time = longest * 0.3 + 2.2  # every hop, plus a beat to read what happened


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
		state.players[pid].coins += won
		result.append([pid, place, won])
	result.sort_custom(func(a, b): return a[1] < b[1])
	state.result = result
	state.round += 1
	state.phase = "final" if state.round > state.rounds else "roll"


static func standings(state: Dictionary) -> Array:
	## pids, best first: most stars, then most coins.
	var pids: Array = state.players.keys()
	pids.sort_custom(func(a, b):
		var pa: Dictionary = state.players[a]
		var pb: Dictionary = state.players[b]
		return pa.stars > pb.stars or (pa.stars == pb.stars and pa.coins > pb.coins))
	return pids
