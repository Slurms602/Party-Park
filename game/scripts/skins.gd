class_name Skins
## Cosmetic catalog. A skin is a small Dictionary of slot -> option id, so it syncs over the network and saves
## to disk as-is. Adding a new cosmetic = one entry here plus its builder in BowlerModel.
## Slots follow Super Battle Golf's loadout layout (hat / upper face / lower face / body / shoes / gloves).

const SLOTS := {
	hat = ["none", "cap", "beanie", "tophat", "cone", "viking", "afro", "mohawk", "propeller", "pin", "party", "headband", "halo"],
	eyes = ["round", "sleepy", "angry", "googly", "cyclops", "shades", "nerd", "visor"],
	mouth = ["grin", "smile", "teeth", "mustache", "tongue", "beard"],
	outfit = ["plain", "bowling", "stripes", "polka", "flames", "tux", "hawaiian", "checker", "zigzag", "galaxy"],
	gloves = ["mitts", "boxing", "cartoon", "gold"],
	shoes = ["classic", "retro", "neon", "tux", "gold"],
	accent = ["red", "blue", "yellow", "green", "purple", "orange", "pink", "teal", "white", "black"],
}

const LABELS := {hat = "Hat", eyes = "Eyes", mouth = "Mouth", outfit = "Outfit", gloves = "Gloves", shoes = "Shoes", accent = "Accent"}

const ACCENTS := {red = Color("e8323c"), blue = Color("2f6bff"), yellow = Color("ffd23f"), green = Color("2ecc71"),
	purple = Color("9b59ff"), orange = Color("ff8c2a"), pink = Color("ff5fb4"), teal = Color("1fd1c1"),
	white = Color("f4f1ea"), black = Color("1c1626")}

const SHOES := {classic = [Color("d93a3a"), Color("2a4fd9")], retro = [Color("efe2c4"), Color("7a4a2a")],
	neon = [Color("39ff88"), Color("ff3fb4")], tux = [Color("16121c"), Color("f4f1ea")], gold = [Color("ffcc33"), Color("b8860b")]}

## Named presets: a starting point for players, and the look of the bots.
const PRESETS := {
	"Classic Bowler": {hat = "none", eyes = "round", mouth = "grin", outfit = "bowling", gloves = "mitts", shoes = "classic", accent = "white"},
	"Pin Head": {hat = "pin", eyes = "googly", mouth = "smile", outfit = "stripes", gloves = "cartoon", shoes = "classic", accent = "red"},
	"Disco Dan": {hat = "afro", eyes = "shades", mouth = "mustache", outfit = "galaxy", gloves = "gold", shoes = "gold", accent = "purple"},
	"Lane Shark": {hat = "cap", eyes = "angry", mouth = "teeth", outfit = "flames", gloves = "boxing", shoes = "neon", accent = "black"},
	"Gutter Punk": {hat = "mohawk", eyes = "angry", mouth = "tongue", outfit = "checker", gloves = "boxing", shoes = "tux", accent = "black"},
	"Pinsetter": {hat = "cone", eyes = "nerd", mouth = "smile", outfit = "zigzag", gloves = "cartoon", shoes = "retro", accent = "orange"},
	"Ten Frame Viking": {hat = "viking", eyes = "cyclops", mouth = "beard", outfit = "tux", gloves = "mitts", shoes = "retro", accent = "teal"},
	"Rad Rollin'": {hat = "headband", eyes = "visor", mouth = "grin", outfit = "hawaiian", gloves = "cartoon", shoes = "neon", accent = "pink"},
}


static func default_skin() -> Dictionary:
	return PRESETS["Classic Bowler"].duplicate()


static func random_skin() -> Dictionary:
	var s := {}
	for slot in SLOTS:
		s[slot] = SLOTS[slot].pick_random()
	return s


static func sanitize(s) -> Dictionary:
	## Skins arrive over the network and from disk: keep only known slots and options.
	var out := default_skin()
	if s is Dictionary:
		for slot in SLOTS:
			if s.get(slot) in SLOTS[slot]:
				out[slot] = s[slot]
	return out


static func cycle(s: Dictionary, slot: String, step: int) -> void:
	var opts: Array = SLOTS[slot]
	s[slot] = opts[(opts.find(s[slot]) + step + opts.size()) % opts.size()]


static func pretty(id: String) -> String:
	return id.capitalize()
