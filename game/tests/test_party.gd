extends SceneTree
## Party rules: rolling, moving, coins, the star, minigame placings and the end.
## Run from the repo root: godot --headless --path game -s tests/test_party.gd

var _fails := 0


func _initialize() -> void:
	var s := Party.new_state([1, 2, 3], 2)
	_check(s.players[1].coins == Party.START_COINS and s.phase == "roll", "everyone starts on the start space with coins")
	var n := Party.roll(s, 1)
	_check(n >= 1 and n <= Party.DICE and Party.roll(s, 1) == 0, "you roll once per round")
	_check(Party.waiting_on(s, [1, 2, 3]) == [2, 3], "the board waits on whoever hasn't rolled")

	# Space 9 holds the star. Player 2 passes it first (fewer steps), player 3 also passes it later.
	s = Party.new_state([1, 2, 3], 2)
	s.players[2].space = 5
	s.players[2].coins = 25
	s.players[3].space = 2
	s.players[3].coins = 40
	s.rolls = {1: 3, 2: 6, 3: 10}
	Party.resolve(s)
	_check(s.players[1].space == 3 and s.players[2].space == 11 and s.players[3].space == 12, "everyone moves at once")
	_check(s.players[2].stars == 1 and s.players[3].stars == 0, "the first to reach the star buys it")
	_check(s.star != 9 and s.star != 0, "then the star moves somewhere else")
	_check(s.players[1].coins == Party.START_COINS - Party.RED and Party.LAYOUT[3] == "R", "red spaces take coins")
	_check(s.players[2].coins - (25 - Party.STAR_COST) in Party.LUCKY and Party.LAYOUT[11] == "L", "stars cost coins (then a lucky space)")
	_check(s.players[3].coins == 40 + Party.BLUE and s.moves[3].events.size() == 1, "blue spaces give coins; a star already taken is just passed")
	_check(s.phase == "move" and s.rolls.is_empty() and s.move_time > 3.0, "then the moves play out")

	s = Party.new_state([1], 2)
	s.players[1].coins = 2
	s.players[1].space = 1
	s.rolls = {1: 2}
	Party.resolve(s)
	_check(s.players[1].coins == 0, "red spaces can't take you below zero")

	s = Party.new_state([1], 2)
	s.players[1].coins = 5
	s.players[1].space = 7
	s.rolls = {1: 4}
	Party.resolve(s)
	_check(s.players[1].stars == 0 and s.moves[1].events[0][0] == "broke" and s.star == 9, "no coins, no star (and it stays put)")

	var g := Party.pick_minigame(s)
	_check(Arena.maps().has(g) and s.phase == "intro", "a minigame is picked")
	var repeats := 0
	for i in 30:
		var before: String = s.last_game
		Party.pick_minigame(s)
		repeats += int(s.last_game == before)
	_check(repeats == 0, "never the same minigame twice in a row")

	s = Party.new_state([1, 2, 3, 4], 2)
	Party.award(s, {1: 30, 2: 30, 3: 12, 4: 0})
	_check(s.players[1].coins == Party.START_COINS + 10 and s.players[2].coins == Party.START_COINS + 10, "a tie shares the place")
	_check(s.players[3].coins == Party.START_COINS + 5 and s.players[4].coins == Party.START_COINS + 3, "then third place, not second")
	_check(s.round == 2 and s.phase == "roll", "next round")
	Party.award(s, {1: 1})
	_check(s.phase == "final", "after the last round the party ends")
	s.players[3].stars = 1
	_check(Party.standings(s)[0] == 3 and Party.standings(s)[1] == 1, "stars beat coins in the standings")

	print("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails)
	quit(1 if _fails else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1
