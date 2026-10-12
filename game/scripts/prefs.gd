extends Node
## Saved player profile and settings (autoload "Prefs"): name, skin, volumes, fullscreen, and progress (see Progress).

const PATH := "user://profile.cfg"

var player_name := ""
var skin := {}
var music := 0.7
var sfx := 0.9
var fullscreen := false
var graphics := "fast" if OS.has_feature("mobile") else "high"  # "high" | "classic" (the original look) | "fast" (phones)
var graphics_checked := false
var show_stats := false  # fps and ping in the corner of the match  # first launch only: drop to classic if this PC can't keep up
var relay := ""  # custom online server URL; empty = Net.DEFAULT_RELAY
var xp := 0
var stats := {}  # lifetime totals: matches, wins, pins
var achievements: Array = []  # Progress.ACHIEVEMENTS ids


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
	graphics = cfg.get_value("video", "graphics", graphics)
	graphics_checked = cfg.get_value("video", "graphics_checked", graphics_checked)
	show_stats = cfg.get_value("video", "show_stats", show_stats)
	if OS.has_feature("mobile") and not graphics_checked and graphics == "classic":
		graphics = "fast"  # phones from before Fast existed
	relay = cfg.get_value("online", "relay", relay)
	xp = cfg.get_value("progress", "xp", xp)
	stats = cfg.get_value("progress", "stats", stats)
	achievements = cfg.get_value("progress", "achievements", achievements)
	apply()


func apply() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(music, 0.001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(sfx, 0.001)))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	var high := graphics == "high"
	var fast := graphics == "fast"
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_4X if high else (Viewport.MSAA_DISABLED if fast else Viewport.MSAA_2X)
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if fast else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.scaling_3d_scale = 0.7 if fast else 1.0  # the 3D renders at 70% and is scaled up; menus and HUD stay sharp
	vp.use_debanding = high
	RenderingServer.directional_shadow_atlas_set_size(2048 if fast else 4096, true)
	var soft := RenderingServer.SHADOW_QUALITY_SOFT_HIGH if high else RenderingServer.SHADOW_QUALITY_SOFT_LOW
	RenderingServer.directional_soft_shadow_filter_set_quality(soft)
	RenderingServer.positional_soft_shadow_filter_set_quality(soft)
	RenderingServer.environment_set_volumetric_fog_volume_size(128 if high else 64, 128 if high else 64)  # crisp light beams


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "skin", skin)
	cfg.set_value("audio", "music", music)
	cfg.set_value("audio", "sfx", sfx)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "graphics", graphics)
	cfg.set_value("video", "graphics_checked", graphics_checked)
	cfg.set_value("video", "show_stats", show_stats)
	cfg.set_value("online", "relay", relay)
	cfg.set_value("progress", "xp", xp)
	cfg.set_value("progress", "stats", stats)
	cfg.set_value("progress", "achievements", achievements)
	cfg.save(PATH)
