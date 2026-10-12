extends SceneTree
## Levels, locks, achievements and unlocks. Restores your saved progress afterwards.
## Run from the repo root: godot --headless --path game -s tests/test_progress.gd

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var prefs: Node = root.get_node("Prefs")  # the autoload (its global name doesn't compile in -s scripts)
	var saved := [prefs.xp, prefs.stats.duplicate(), prefs.achievements.duplicate()]
	prefs.xp = 0
	prefs.stats = {}
	prefs.achievements = []

	_check(Progress.level_info(0).level == 1 and Progress.level_info(100).level == 2, "100 XP reaches level 2")
	var l := Progress.level_info(224)
	_check(l.level == 2 and l.into == 124 and l.need == 125, "level 2 needs 125 more")
	_check(Progress.lock_reason("hat", "cap") == "", "old cosmetics stay free")
	_check(Progress.lock_reason("hat", "cowboy") == "Reach level 3", "cowboy hat waits for level 3")
	_check(Progress.lock_reason("hat", "crown").begins_with("Dynasty"), "crown waits for Dynasty")
	var bad := []
	for reward in Progress.LEVEL_REWARDS.values() + Progress.ACHIEVEMENTS.values().filter(func(a): return a.has("reward")).map(func(a): return a.reward):
		if not reward[1] in Skins.SLOTS[reward[0]]:
			bad.append(reward)
	_check(bad.is_empty(), "every reward is a real cosmetic %s" % [bad])

	var row := {total = 60, kos = 2, strikes = 3, spares = 0, rolls = ["X", "X", "X", "5"]}
	var p := Progress.finish_match(row, true, {pins = 35})
	_check(p.achievements == ["first_frame", "champion", "hat_trick", "turkey"], "a winning 3-strike match earns 4 achievements (%s)" % [p.achievements])
	_check(p.xp == 25 + 60 + 10 + 50 + 4 * Progress.ACHIEVEMENT_XP, "XP = finish + points + KOs + win + achievements (%d)" % p.xp)
	_check(p.after.level == 3 and p.unlocks.has(["hat", "cowboy"]) and p.unlocks.has(["hat", "golden_pin"]), "level 3: cowboy and golden pin unlocked")
	_check(Progress.lock_reason("hat", "cowboy") == "" and Progress.lock_reason("accent", "gold") == "", "unlocked items can be worn")
	var again := Progress.finish_match(row, false, {})
	_check(again.achievements.is_empty() and again.xp == 25 + 60 + 10, "achievements only pay out once")
	for i in 8:
		Progress.finish_match({total = 0, kos = 0, strikes = 0, spares = 0, rolls = ["F", "F", "F"]}, false, {})
	_check(prefs.achievements.has("league") and prefs.achievements.has("foul_play"), "10 matches and 3 fouls count")
	var skin := Skins.random_skin()
	_check(Skins.SLOTS.keys().all(func(s): return Progress.lock_reason(s, skin[s]) == ""), "random looks only use unlocked items")

	prefs.xp = saved[0]
	prefs.stats = saved[1]
	prefs.achievements = saved[2]
	prefs.save()
	print("ALL PASSED" if _fails == 0 else "%d FAILED" % _fails)
	quit(1 if _fails else 0)


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1
