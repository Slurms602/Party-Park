## Bowling your Friends: knock people out, then bowl them into the pins. This folder is its own git repo.
## MAPS is what the game knows about this minigame (see Arena.maps): one entry per alley.
## name: on the party board · map: in the lobby · seconds: a party round · dark: dark UI · menu: plays behind the menu

const MAPS := {
	classic = {name = "Cosmic Bowling", map = "Cosmic Lanes", rules = "Knock them out, bowl them into the pins. Most points wins.",
		seconds = 75.0, dark = true, menu = true, arena = preload("bowling_arena.gd")},
	sunset = {name = "Sunset Bowling", map = "Sunset Lanes", rules = "Longer lanes, bigger pins. Most points wins.",
		seconds = 75.0, menu = true, arena = preload("sunset_arena.gd")},
}
