extends Node
## Music (autoload "Music"). Same idea as Super Battle Golf's music: a menu theme, a match theme that
## switches to a faster "hurry" version for the final stretch, and a results jingle. Tracks are rendered
## by tools/make_music.py.

const TRACKS := {menu = "res://assets/music/menu.ogg", match = "res://assets/music/match.ogg",
	hurry = "res://assets/music/match_hurry.ogg", victory = "res://assets/music/victory.ogg"}

var current := ""
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _duck: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		_players.append(p)


func play(track: String, fade := 1.2) -> void:
	if track == current:
		return
	current = track
	var stream: AudioStream = load(TRACKS[track])
	if stream is AudioStreamOggVorbis:
		stream.loop = track != "victory"
	var old := _players[_active]
	_active = 1 - _active
	var p := _players[_active]
	p.stream = stream
	p.volume_db = -30.0 if fade > 0.0 else 0.0
	p.play()
	var tw := create_tween().set_parallel()
	tw.tween_property(p, "volume_db", 0.0, fade)
	tw.tween_property(old, "volume_db", -40.0, fade)
	tw.chain().tween_callback(old.stop)


func duck(seconds := 1.5) -> void:
	## Dip the music under a big jingle (STRIKE!, the countdown).
	if _duck:
		_duck.kill()
	var p := _players[_active]
	_duck = create_tween()
	_duck.tween_property(p, "volume_db", -9.0, 0.08)
	_duck.tween_interval(seconds)
	_duck.tween_property(p, "volume_db", 0.0, 0.6)
