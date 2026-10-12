extends SceneTree
## Party rules: rolling, items, moving, forks, the spaces and landmarks, the star, minigame placings, bonus stars.
## Run from the repo root: godot --headless --path game -s tests/test_party.gd

var _fails := 0


func _initialize() -> void:
	var s := Party.new_state([1, 2, 3], 2)
	_check(s.players[1].coins == Party.START_COINS and s.phase == "roll" and s.star in Party.STAR_SPOTS, "everyone starts at the gate")
	var n := Party.roll(s, 1)
	_check(n >= 1 and n <= Party.DICE and Party.roll(s, 1) == 0, "you roll once per round")
	_check(Party.waiting_on(s, [1, 2, 3]) == [2, 3], "the board waits on whoever hasn't rolled")
	_check(Party.steps_to(7, 25) == 14 and Party.steps_to(0, 7) == 7, "the plaza shortcut is the short way round")
	for i in Party.SPACES.size():  # every space leads somewhere real, and the loop gets back to the start
		for nx in Party.next_spaces(i):
			if nx < 0 or nx >= Party.SPACES.size():
				_check(false, "space %d leads off the board" % i)
	_check(Party.steps_to(1, 0) < 99 and Party.steps_to(53, 0) < 99, "every way leads back to the gate")

	# Moving: blue and red spaces, and everyone moves at once.
	s = Party.new_state([1, 2], 2)
	s.star = 50
	s.players[1].space = 3
	s.players[2].space = 2
	s.rolls = {1: 2, 2: 2}
	Party.resolve(s)
	_check(s.players[1].space == 5 and s.players[1].coins == Party.START_COINS + Party.BLUE, "blue spaces give coins")
	_check(s.players[2].space == 4 and s.players[2].coins == Party.START_COINS - Party.RED, "red spaces take coins")
	_check(s.phase == "move" and s.rolls.is_empty() and s.moves[1].path == [4, 5], "then the moves play out")
	s = Party.new_state([1], 2)
	s.star = 50
	s.players[1].space = 1
	s.rolls = {1: 2}
	Party.resolve(s)
	_check(s.bank == Party.BOOTH and s.players[1].coins == Party.START_COINS - Party.BOOTH + Party.BLUE, "passing the ticket booth costs coins")

	s = Party.new_state([1], 2)
	s.star = 50
	s.bank = 12
	s.players[1].space = 1
	s.rolls = {1: 1}
	Party.resolve(s)
	_check(s.players[1].coins == Party.START_COINS + 12 and s.bank == 0, "landing on the ticket booth wins the bank")

	s = Party.new_state([1], 2)
	s.star = 50
	s.players[1].coins = 2
	s.players[1].space = 3
	s.rolls = {1: 1}
	Party.resolve(s)
	_check(s.players[1].coins == 0, "red spaces can't take you below zero")

	# The star: whoever reaches it first (fewest steps) and can pay buys it. Then it moves.
	s = Party.new_state([1, 2, 3], 2)
	s.star = 13
	s.players[2].space = 9
	s.players[2].coins = 25
	s.players[3].space = 8
	s.players[3].coins = 40
	s.rolls = {1: 1, 2: 6, 3: 10}
	Party.resolve(s)
	_check(s.players[2].stars == 1 and s.players[3].stars == 0 and s.star != 13, "the first to reach the star buys it, then it moves")
	_check(s.players[2].space == Party.COASTER_TO and s.moves[2].warp == Party.COASTER_TO, "the roller coaster takes you across the park")
	s = Party.new_state([1], 2)
	s.star = 13
	s.players[1].space = 10
	s.players[1].coins = 5
	s.rolls = {1: 6}
	Party.resolve(s)
	_check(s.players[1].stars == 0 and s.moves[1].events[0][0] == "broke" and s.star == 13, "no coins, no star (and it stays put)")

	# Forks: you stop and pick a way; landing right on one doesn't stop you.
	s = Party.new_state([1, 2], 2)
	s.star = 50
	s.players[1].space = 5
	s.players[2].space = 5
	s.rolls = {1: 5, 2: 2}
	Party.resolve(s)
	_check(s.players[1].space == 7 and s.forks.has(1) and s.left[1] == 3 and not s.forks.has(2), "a fork stops you with steps left")
	Party.after_move(s)
	_check(s.phase == "choose" and not Party.choose(s, 1, 20) and not Party.choose(s, 2, 8), "then you pick one of its ways")
	_check(Party.choose(s, 1, 39) and s.phase == "move" and s.moves[1].path == [39, 40, 41] and s.players[1].space == 41, "and carry on that way")
	Party.after_move(s)
	_check(s.phase == "intro", "then it's minigame time")

	# Items.
	s = Party.new_state([1, 2, 3], 2)
	s.star = 50
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
	s.players[1].items = ["golden"]
	Party.use_item(s, 1, 0)
	_check(Party.next_spaces(s.players[1].space).has(s.star), "Golden Ticket warps you next to the star")
	Party.roll(s, 1)
	s.players[1].items = ["double"]
	_check(not Party.use_item(s, 1, 0), "no items after you've rolled")

	s = Party.new_state([1], 2)
	s.star = 50
	s.players[1].space = 5
	s.players[1].items = ["swap", "swap"]
	s.rolls = {1: 1}
	Party.resolve(s)
	_check(s.players[1].items.size() == Party.BAG and s.players[1].coins == Party.START_COINS + Party.BLUE, "a full bag gets coins instead")

	# Landmarks.
	s = Party.new_state([1, 2, 3], 2)
	s.star = 50
	s.players[1].space = 29
	s.players[2].space = 31
	s.players[3].space = 0
	s.rolls = {1: 1}
	Party.resolve(s)
	_check(s.players[1].coins == Party.START_COINS + 3 and s.players[2].coins == Party.START_COINS - 3
		and s.players[3].coins == Party.START_COINS and s.players[1].events == 1, "a strike at the bowling alley bowls over whoever's near")
	s = Party.new_state([1, 2], 2)
	s.star = 50
	s.players[1].space = 9
	s.players[2].space = 11
	s.rolls = {1: 1}
	Party.resolve(s)
	var duel: Array = s.moves[1].events[0]
	_check(duel[0] == "duel" and duel[1] == 2 and s.players[1].coins + s.players[2].coins == 2 * Party.START_COINS
		and (duel[4] > 0) == (duel[2] > duel[3]) and (duel[4] == 0) == (duel[2] == duel[3]), "the sumo dojo: a duel, higher roll takes coins")

	# Minigames and the end.
	var g := Party.pick_minigame(s)
	_check(Arena.maps().has(g) and s.phase == "intro", "a minigame is picked")
	var repeats := 0
	for i in 30:
		var last: String = s.last_game
		Party.pick_minigame(s)
		repeats += int(s.last_game == last)
	_check(repeats == 0, "never the same minigame twice in a row")

	s = Party.new_state([1, 2, 3, 4], 2)
	Party.award(s, {1: 30, 2: 30, 3: 12, 4: 0})
	_check(s.players[1].coins == Party.START_COINS + 10 and s.players[2].coins == Party.START_COINS + 10, "a tie shares the place")
	_check(s.players[3].coins == Party.START_COINS + 5 and s.players[4].coins == Party.START_COINS + 3, "then third place, not second")
	_check(s.round == 2 and s.phase == "roll", "next round")
	s.players[3].events = 2
	Party.award(s, {1: 1})
	_check(s.phase == "final", "after the last round the party ends")
	_check(s.bonus.size() == 3 and s.players[3].stars == 1 and s.players[1].stars == 2, "bonus stars: minigames, coins, events")
	_check(Party.standings(s)[0] == 1, "stars beat coins in the standings")

	print("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails)
	quit(1 if _fails else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1
