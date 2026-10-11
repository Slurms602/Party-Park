extends Node
## Saved player profile and settings (autoload "Prefs"): name, skin, volumes, fullscreen.

const PATH := "user://profile.cfg"

var player_name := ""
var skin := {}
var music := 0.7
var sfx := 0.9
var fullscreen := false
var relay := ""  # custom online server URL; empty = Net.DEFAULT_RELAY


func _ready() -> void:
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	player_name = cfg.get_value("player", "name", "Bowler%d" % (randi() % 100))
	skin = Skins.sanitize(cfg.get_value("player", "skin", Skins.PRESETS.values().pick_random()))
	music = cfg.get_value("audio", "music", music)
	sfx = cfg.get_value("audio", "sfx", sfx)
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	relay = cfg.get_value("online", "relay", relay)
	apply()


func apply() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(music, 0.001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(sfx, 0.001)))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "skin", skin)
	cfg.set_value("audio", "music", music)
	cfg.set_value("audio", "sfx", sfx)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("online", "relay", relay)
	cfg.save(PATH)
