extends SceneTree
## Party rules: the map, rolling, items, moving, forks and tolls, shops and the mascot, every kind of space and each
## zone's happening, the trophy, the show, minigame placings, the final round and the bonus trophies.
## Run from the repo root: godot --headless --path game -s tests/test_party.gd

var _fails := 0


func _initialize() -> void:
	# The map.
	var n := Party.SPACES.size()
	_check(n >= 120, "a big board (%d spaces)" % n)
	var ok := true
	var close := true
	for i in n:
		for nx in Party.next_spaces(i):
			ok = ok and nx >= 0 and nx < n and Party.steps_to(nx, 0) < 999
		for j in range(i + 1, n):
			close = close and Party.pos(i).distance_to(Party.pos(j)) > 2.6
	_check(ok, "every space leads somewhere real, and back round to the start")
	_check(close, "no two spaces on top of each other")
	_check(range(n).all(func(i): return Party.steps_to(0, i) < 999), "every space can be reached")
	_check(Party.FORKS.size() == 4 and Party.TOLLS.size() == 2, "four forks, two of them toll ways")
	_check(Party.STAR_SPOTS.all(func(i): return Party.kind(i) == "B"), "the trophy only stands on blue spaces")
	_check(Party.steps_to(1, Party.BASE) < Party.steps_to(2, Party.BASE) - 8, "the stadium tunnel is a real shortcut")
	for k in "SBRIKHFT$MDPC":
		_check(range(n).any(func(i): return Party.kind(i) == k), "there's a %s space" % k)

	var s := Party.new_state([1, 2, 3], 2)
	_check(s.phase == "tour" and Party.roll(s, 1) == 0, "the party opens with a tour of the park")
	Party.begin(s)
	_check(s.players[1].coins == Party.START_COINS and s.phase == "roll" and s.star in Party.STAR_SPOTS, "then everyone starts at the gate")
	var r := Party.roll(s, 1)
	_check(r >= 1 and r <= Party.DICE and Party.roll(s, 1) == 0, "you roll once per round")
	_check(Party.waiting_on(s, [1, 2, 3]) == [2, 3], "the board waits on whoever hasn't rolled")

	# Blue and red spaces, everyone moving at once.
	s = _state([1, 2])
	s.players[1].space = 4
	s.players[2].space = 4
	s.rolls = {1: 2, 2: 1}
	Party.resolve(s)
	_check(s.players[1].space == 6 and s.players[1].coins == Party.START_COINS + Party.BLUE, "blue spaces give coins")
	_check(s.players[2].space == 5 and s.players[2].coins == Party.START_COINS - Party.RED, "red spaces take coins")
	_check(s.phase == "move" and s.rolls.is_empty() and s.moves[1].path == [5, 6], "then the moves play out")
	s = _state([1])
	s.players[1].coins = 2
	s.players[1].space = 4
	s.rolls = {1: 1}
	Party.resolve(s)
	_check(s.players[1].coins == 0, "red spaces can't take you below zero")

	# Forks and tolls.
	s = _state([1, 2])
	s.players[1].coins = 5
	s.players[1].space = 0
	s.players[2].coins = 30
	s.players[2].space = 0
	s.rolls = {1: 3, 2: 3}
	Party.resolve(s)
	_check(s.players[1].space == 1 and s.stops[1].kind == "fork" and s.left[1] == 2, "a fork stops you with steps left")
	Party.after_move(s)
	_check(s.phase == "choose" and not Party.choose(s, 1, 87) and not Party.choose(s, 1, 50), "the stadium tunnel costs 8 coins")
	_check(Party.choose(s, 2, 87) and s.players[2].coins == 22 and not s.stops.has(2), "pay up and it's yours")
	_check(Party.choose(s, 1, 2) and s.phase == "move" and s.moves[1].path == [2, 3] and s.moves[2].path == [87, 88], "and on you go")
	_check(s.stops[1].kind == "shop" and s.bank == Party.BOOTH and s.players[1].coins == 2,
		"passing the ticket booth banks coins; the pro shop stops you")

	# The pro shop.
	Party.after_move(s)
	_check(s.stops[1].options.size() == 4 and s.stops[1].options[-1] == "pass", "the shop offers three items")
	s.stops[1].options = ["drink", "golden", "double", "pass"]
	s.players[1].coins = 5
	_check(not Party.choose(s, 1, "golden"), "you can't buy what you can't afford")
	_check(Party.choose(s, 1, "drink") and s.players[1].items == ["drink"] and s.players[1].coins == 2, "buy one and it goes in your bag")
	s = _state([1])
	s.players[1].space = 1
	s.picks = {1: 2}
	s.bank = 12
	s.rolls = {1: 1}
	Party.resolve(s)
	_check(s.players[1].coins == Party.START_COINS + 12 and s.bank == 0, "landing on the ticket booth wins the bank")

	# The trophy: whoever reaches it first (fewest steps) and can pay wins it. Then it moves.
	s = _state([1, 2, 3])
	s.star = 6
	s.players[2].space = 5
	s.players[2].coins = 25
	s.players[3].space = 4
	s.players[3].coins = 40
	s.rolls = {1: 1, 2: 1, 3: 2}
	Party.resolve(s)
	_check(s.players[2].stars == 1 and s.players[3].stars == 0 and s.star != 6, "the first to reach the trophy wins it, then it moves")
	_check(s.show[0][0] == "trophy" and s.show[1][0] == "trophy_move", "both make a show")
	Party.after_move(s)
	_check(s.phase == "show" and is_equal_approx(s.show_time, Party.SHOW.trophy + Party.SHOW.trophy_move), "which everyone watches")
	Party.after_show(s)
	_check(s.phase == "intro" and s.show.is_empty(), "then it's minigame time")
	s = _state([1])
	s.star = 6
	s.players[1].space = 4
	s.players[1].coins = 5
	s.rolls = {1: 4}
	Party.resolve(s)
	_check(s.players[1].stars == 0 and s.moves[1].events[0][0] == "broke" and s.star == 6, "no coins, no trophy (and it stays put)")

	# Items.
	s = _state([1, 2, 3])
	s.players[1].items = ["double", "magnet", "swap"]
	s.players[2].coins = 30
	s.players[2].space = 10
	s.players[3].space = 20
	_check(not Party.use_item(s, 1, 5) and Party.use_item(s, 1, 0) and s.doubled.has(1), "Double Dice")
	var two_dice := false
	for k in 40:
		s.rolls.erase(1)
		two_dice = two_dice or Party.roll(s, 1) > Party.DICE
	_check(two_dice, "...rolls two dice")
	s.rolls.erase(1)
	_check(Party.use_item(s, 1, 0) and s.players[2].coins == 25 and s.players[1].coins == Party.START_COINS + 5, "Coin Magnet takes from the richest")
	var before: int = s.players[1].space
	Party.use_item(s, 1, 0)
	_check(s.players[1].space != before and s.players[1].items.is_empty(), "Swap Ticket trades places")
	s.players[1].items = ["golden", "drink", "whistle"]
	Party.use_item(s, 1, 0)
	_check(Party.next_spaces(s.players[1].space).has(s.star), "Golden Ticket warps you next to the trophy")
	Party.use_item(s, 1, 0)
	s.doubled.erase(1)
	_check(Party.roll(s, 1) > 3, "Energy Drink: +3")
	s.rolls.erase(1)
	s.players[2].stars = 1
	var c2: int = s.players[2].coins
	Party.use_item(s, 1, 0)
	_check(s.players[2].coins == c2 - 10, "the Ref's Whistle books the leader")
	Party.roll(s, 1)
	s.players[1].items = ["double"]
	_check(not Party.use_item(s, 1, 0), "no items after you've rolled")
	s = _state([1])
	s.players[1].space = 4
	s.players[1].items = ["swap", "swap", "swap"]
	s.rolls = {1: 4}
	Party.resolve(s)
	_check(s.players[1].items.size() == Party.BAG and s.players[1].coins == Party.START_COINS + Party.BLUE, "a full bag gets coins instead")

	# Each zone's happening.
	s = _land_on(Party.LEG.speedway + 1)
	_check(s.players[1].space == Party.ahead(Party.LEG.speedway + 1, 6) and s.show[0][0] == "pitstop", "speedway: a ride in a race car")
	s = _land_on(Party.LEG.trail + 4, {2: Party.LEG.trail + 9, 3: 0})
	_check(s.players[2].space == Party.BASE and s.players[3].space == 0 and s.players[1].space == Party.LEG.trail + 4
		and s.show[0][0] == "avalanche", "mountain: an avalanche sweeps everyone else down")
	s = _land_on(Party.LEG.trail + 4)
	_check(s.players[1].space == Party.BASE, "...or you, if you're alone up there")
	s = _land_on(Party.LEG.ballpark + 1)
	_check(s.players[1].space != Party.LEG.ballpark + 1 and Party.kind(s.players[1].space) == "B" and s.show[0][0] == "homerun",
		"ballpark: hit for a home run")
	s = _land_on(Party.LEG.stadium + 6, {2: Party.LEG.stadium + 11, 3: 0})
	_check(s.players[1].coins == Party.START_COINS + 8 and s.players[2].coins == Party.START_COINS + 4
		and s.players[3].coins == Party.START_COINS, "stadium: the wave showers whoever's inside")
	s = _land_on(Party.LEG.fairway + 1, {2: 0})
	_check(s.players[1].coins == Party.START_COINS + 5 and s.players[2].coins == Party.START_COINS - 5 and s.show[0][0] == "fore",
		"golf: FORE! conks someone and you pocket their coins")
	s = _land_on(Party.LEG.shore + 3)
	_check(s.players[1].coins < Party.START_COINS and s.show[0][0] == "gulls", "beach: seagulls")
	s = _land_on(Party.LEG.plazaw + 5)
	_check(s.players[1].items.size() == 1 and s.show[0][0] == "cannon", "plaza: a prize from the T-shirt cannon")
	s = _land_on(Party.LEG.courts + 3)
	_check(s.players[1].coins >= Party.START_COINS + 5 and s.show[0][0] == "dunk", "courts: a slam dunk")
	_check(s.players[1].events == 1, "happenings count toward the Hustle Award")

	# The referee, Trade Deadline, the ski jump, the alley, the dojo, the mascot.
	for k in 20:
		s = _land_on(Party.LEG.golf + 7, {2: 0})
		var call: Array = s.show[0]
		var p: Dictionary = s.players[1]
		var fair := false
		match call[2]:
			"yellow": fair = p.coins == 0
			"offside": fair = Party.steps_to(p.space, Party.LEG.golf + 7) == 5
			"penalty": fair = p.coins == Party.START_COINS - 3 and s.players[2].coins == Party.START_COINS + 3
			"red": fair = p.space == 0 and p.coins == Party.START_COINS - 5
			"cap": fair = p.coins == s.players[2].coins
		if not fair:
			_check(false, "the ref's call (%s) does what it says" % call[2])
			break
	_check(true, "the referee's calls do what they say")
	for k in 20:
		s = _land_on(Party.LEG.speedway + 4, {2: 0, 3: 0})
		var total := 0
		for pid in s.players:
			total += s.players[pid].coins
		if s.show[0][0] != "trade" or (s.show[0][4] != "trophy" and s.show[0][4] != "swap_trophies" and total != 3 * Party.START_COINS):
			_check(false, "Trade Deadline moves coins between players (%s)" % s.show[0][4])
			break
	_check(true, "Trade Deadline moves coins between players, never makes them")
	s = _land_on(Party.LEG.descent, {}, Party.LIFT[1])
	_check(s.players[1].space == Party.SKI_TO and s.show[0][0] == "ski", "the ski jump flies you down the mountain")
	s = _land_on(Party.LEG.bowling + 2, {2: Party.LEG.bowling + 3, 3: 0})
	_check(s.players[1].coins == Party.START_COINS + 3 and s.players[2].coins == Party.START_COINS - 3
		and s.players[3].coins == Party.START_COINS and s.show[0][0] == "strike", "a strike at the bowling alley bowls over whoever's near")
	s = _land_on(Party.LEG.dojo + 1, {2: Party.LEG.dojo + 3})
	var duel: Array = s.show[0]
	_check(duel[0] == "duel" and duel[2] == 2 and s.players[1].coins + s.players[2].coins == 2 * Party.START_COINS
		and (duel[5] > 0) == (duel[3] > duel[4]), "the sumo dojo: a duel, higher roll takes coins")
	s = _land_on(Party.LEG.ballpark + 3, {2: 0, 3: 0})
	s.players[2].coins = 30
	_check(s.stops[1].kind == "mascot" and s.stops[1].options == ["steal", "pass"], "the mascot offers its services")
	Party.after_move(s)
	_check(Party.choose(s, 1, "steal") and s.players[1].coins == Party.START_COINS - 5 + 10 and s.players[2].coins == 20,
		"pay it and it pinches coins from the richest")

	# Minigames and the end.
	var g := Party.pick_minigame(s)
	_check(Arena.maps().has(g) and s.phase == "intro", "a minigame is picked")
	var repeats := 0
	for i in 30:
		var last: String = s.last_game
		Party.pick_minigame(s)
		repeats += int(s.last_game == last)
	_check(repeats == 0, "never the same minigame twice in a row")

	s = _state([1, 2, 3, 4])
	Party.award(s, {1: 30, 2: 30, 3: 12, 4: 0})
	_check(s.players[1].coins == Party.START_COINS + 10 and s.players[2].coins == Party.START_COINS + 10, "a tie shares the place")
	_check(s.players[3].coins == Party.START_COINS + 5, "then third place, not second")
	_check(s.round == 2 and s.phase == "roll" and Party.frenzy(s) and s.players[4].coins == Party.START_COINS + 3 + Party.FRENZY_BONUS,
		"the final round: last place gets a leg-up")
	s.players[1].space = 4
	s.rolls = {1: 2}
	Party.resolve(s)
	_check(s.players[1].coins == Party.START_COINS + 10 + 2 * Party.BLUE, "and blue spaces count double")
	s.players[3].events = 2
	Party.award(s, {1: 1})
	_check(s.phase == "final", "after the last round the party ends")
	_check(s.bonus.size() == 3 and s.players[3].stars == 1 and s.players[1].stars == 2, "bonus trophies: minigames, coins, events")
	_check(Party.standings(s)[0] == 1, "trophies beat coins in the standings")

	print("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails)
	quit(1 if _fails else 0)


func _state(pids: Array) -> Dictionary:
	var s := Party.new_state(pids, 2)
	Party.begin(s)
	s.star = Party.STAR_SPOTS[-1]
	return s


func _land_on(space: int, others := {}, from := -1) -> Dictionary:
	## Player 1 rolls a 1 onto `space`; others: pid -> where they stand.
	var s := _state([1] + others.keys())
	s.star = Party.LEG.plaza + 2  # out of everyone's way
	s.players[1].space = from if from >= 0 else Party.before(space)
	for pid in others:
		s.players[pid].space = others[pid]
	s.rolls = {1: 1}
	Party.resolve(s)
	return s


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1
