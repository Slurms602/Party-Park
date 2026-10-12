class_name Progress
## XP, levels, achievements and the cosmetics they unlock (Super Battle Golf's CosmeticsUnlocksManager:
## cosmetics "unlocked by achievement"). Progress lives on each player's own device, in Prefs.
## Anything in Skins.SLOTS that isn't a reward below is free from the start.

const ACHIEVEMENTS := {
	first_frame = {name = "First Frame", desc = "Finish a match", reward = ["shoes", "ice"]},
	champion = {name = "Champion", desc = "Win a match", reward = ["accent", "gold"]},
	league = {name = "League Night", desc = "Play 10 matches", reward = ["shoes", "candy"]},
	dynasty = {name = "Dynasty", desc = "Win 10 matches", reward = ["hat", "crown"]},
	hat_trick = {name = "Hat Trick", desc = "3 strikes in one match", reward = ["eyes", "sparkle"]},
	turkey = {name = "Turkey", desc = "3 strikes in a row", reward = ["hat", "golden_pin"]},
	spare_me = {name = "Spare Me", desc = "3 spares in one match", reward = ["mouth", "kiss"]},
	ko_artist = {name = "Knockout Artist", desc = "5 knockouts in one match", reward = ["mouth", "fangs"]},
	midas = {name = "Midas Touch", desc = "Strike with a Golden Ball", reward = ["outfit", "gold"]},
	buzzer = {name = "Buzzer Beater", desc = "Strike in the last 10 seconds", reward = ["outfit", "rainbow"]},
	fastball = {name = "Fastball", desc = "Hit someone with a thrown bowling ball", reward = ["gloves", "diamond"]},
	foul_play = {name = "Foul Play", desc = "3 fouls in one match", reward = ["hat", "dunce"]},
	century = {name = "Century", desc = "Score 100 points in one match", xp = 150},
	collateral = {name = "Collateral Damage", desc = "Bowl a body into someone", xp = 100},
	pin_collector = {name = "Pin Collector", desc = "Knock down 500 pins", xp = 200},
}
const LEVEL_REWARDS := {2: ["shoes", "flame"], 3: ["hat", "cowboy"], 4: ["eyes", "laser"], 5: ["outfit", "tiger"],
	6: ["hat", "chef"], 7: ["gloves", "lava"], 8: ["hat", "bunny"], 10: ["outfit", "lava"], 12: ["hat", "wizard"]}
const ACHIEVEMENT_XP := 50  # on top of any cosmetic

static var fresh: Array = []  # rewards from the last match, for the menu to announce


static func _prefs() -> Node:
	# Looked up at runtime so this class also compiles in headless tests, where autoloads don't exist yet.
	return (Engine.get_main_loop() as SceneTree).root.get_node("Prefs")


static func xp_for(level: int) -> int:
	## XP to go from `level` to the next one: early levels come about once a match, later ones slower.
	return 100 + 25 * (level - 1)


static func level_info(xp: int) -> Dictionary:
	var lvl := 1
	while xp >= xp_for(lvl):
		xp -= xp_for(lvl)
		lvl += 1
	return {level = lvl, into = xp, need = xp_for(lvl)}


static func lock_reason(slot: String, id: String) -> String:
	## "" when you can wear it, otherwise how to get it.
	var reward := [slot, id]
	for lvl in LEVEL_REWARDS:
		if LEVEL_REWARDS[lvl] == reward:
			return "" if level_info(_prefs().xp).level >= lvl else "Reach level %d" % lvl
	for a: String in ACHIEVEMENTS:  # String, not StringName: Array.has() won't match the two
		if ACHIEVEMENTS[a].get("reward") == reward:
			return "" if _prefs().achievements.has(a) else "%s: %s" % [ACHIEVEMENTS[a].name, ACHIEVEMENTS[a].desc.to_lower()]
	return ""


static func reward_name(reward: Array) -> String:
	return "%s %s" % [Skins.pretty(reward[1]), Skins.LABELS[reward[0]].to_lower()]


static func finish_match(row: Dictionary, won: bool, feats: Dictionary) -> Dictionary:
	## Bank a finished match for the local player. Returns what to show on the results screen.
	var prefs := _prefs()
	var st: Dictionary = prefs.stats
	for k in ["matches", "wins", "pins"]:
		st[k] = st.get(k, 0)
	st.matches += 1
	st.wins += int(won)
	st.pins += feats.get("pins", 0)
	var rolls: Array = row.get("rolls", [])
	var hit := {
		first_frame = true, champion = won, league = st.matches >= 10, dynasty = st.wins >= 10,
		hat_trick = row.get("strikes", 0) >= 3, turkey = "XXX" in "".join(rolls), spare_me = row.get("spares", 0) >= 3,
		ko_artist = row.get("kos", 0) >= 5, midas = feats.get("midas", false), buzzer = feats.get("buzzer", false),
		fastball = feats.get("fastball", false), foul_play = rolls.count("F") >= 3, century = row.get("total", 0) >= 100,
		collateral = feats.get("collateral", false), pin_collector = st.pins >= 500,
	}
	var before := level_info(prefs.xp)
	var xp: int = 25 + row.get("total", 0) + 5 * row.get("kos", 0) + (50 if won else 0)
	var got := []
	var unlocks := []
	for a: String in ACHIEVEMENTS:
		if hit[a] and not prefs.achievements.has(a):
			prefs.achievements.append(a)
			got.append(a)
			xp += ACHIEVEMENT_XP + ACHIEVEMENTS[a].get("xp", 0)
			if ACHIEVEMENTS[a].has("reward"):
				unlocks.append(ACHIEVEMENTS[a].reward)
	prefs.xp += xp
	var after := level_info(prefs.xp)
	for lvl in range(before.level + 1, after.level + 1):
		if LEVEL_REWARDS.has(lvl):
			unlocks.append(LEVEL_REWARDS[lvl])
	prefs.save()
	return {xp = xp, before = before, after = after, achievements = got, unlocks = unlocks}
