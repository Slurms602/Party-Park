extends Node
## Sound effects synthesized at startup (autoload "Sfx"), so the repo needs no audio assets.

const RATE := 22050
var _clips := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _ui: AudioStreamPlayer


func _ready() -> void:
	_clips.punch = _make(0.14, func(t): return sin(TAU * 95.0 * t) * exp(-t * 30.0) + _n() * exp(-t * 90.0) * 0.6)
	_clips.smack = _make(0.32, func(t): return sin(TAU * 60.0 * t) * exp(-t * 14.0) + _n() * exp(-t * 25.0) * 0.8)
	_clips.whiff = _make(0.18, func(t): return _n() * sin(PI * t / 0.18) * 0.35)
	_clips.pins = _make(0.9, _pins_wave())
	_clips.ko = _make(0.6, func(t): return sin(TAU * (1300.0 * t - 750.0 * t * t)) * (1.0 - t / 0.6) * 0.6)
	_clips.wake = _make(0.35, func(t): return sin(TAU * (300.0 + 500.0 * t) * t + sin(TAU * 18.0 * t) * 2.0) * (1.0 - t / 0.35) * 0.5)
	_clips.bowl = _make(0.5, func(t): return _n() * sin(PI * t / 0.5) * 0.5 + sin(TAU * 70.0 * t) * 0.3 * sin(PI * t / 0.5))
	_clips.strike = _make(1.2, _arp([523.0, 659.0, 784.0, 1047.0, 1319.0]))
	_clips.spare = _make(0.8, _arp([392.0, 523.0, 659.0]))
	_clips.thud = _make(0.2, func(t): return sin(TAU * 50.0 * t) * exp(-t * 20.0))
	_clips.buzzer = _make(1.0, func(t): return signf(sin(TAU * 110.0 * t)) * 0.25 * (1.0 - t))
	for i in 24:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 8.0
		p.max_distance = 60.0
		add_child(p)
		_pool.append(p)
	_ui = AudioStreamPlayer.new()
	add_child(_ui)


func play(clip: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if not _clips.has(clip):
		return
	for p in _pool:
		if not p.playing:
			p.stream = _clips[clip]
			p.global_position = pos
			p.volume_db = volume_db
			p.pitch_scale = pitch * randf_range(0.92, 1.08)
			p.play()
			return


func play_ui(clip: String, volume_db := 0.0) -> void:
	_ui.stream = _clips.get(clip)
	_ui.volume_db = volume_db
	_ui.play()


func _n() -> float:
	return randf() * 2.0 - 1.0


func _make(seconds: float, wave: Callable) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(wave.call(float(i) / RATE), -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	return s


func _pins_wave() -> Callable:
	# A pile of short wooden "tok"s at random times and pitches.
	var hits := []
	for i in 14:
		hits.append([randf() * 0.35, randf_range(700.0, 2400.0), randf_range(0.3, 1.0)])
	return func(t):
		var v := _n() * exp(-t * 12.0) * 0.25
		for h in hits:
			var dt: float = t - h[0]
			if dt > 0.0:
				v += sin(TAU * h[1] * dt) * exp(-dt * 40.0) * h[2] * 0.35
		return v


func _arp(notes: Array) -> Callable:
	var step := 0.12
	return func(t):
		var i := mini(int(t / step), notes.size() - 1)
		var dt: float = t - i * step
		return (sin(TAU * notes[i] * t) + 0.3 * signf(sin(TAU * notes[i] * 2.0 * t))) * exp(-dt * 4.0) * 0.4
