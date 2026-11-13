extends Node
class_name EngineAudio
## Procedural engine + wind: short seamless loops synthesised at start-up
## (no audio files), then pitch/volume modulated by throttle and airspeed.
## Mixed quietly so it sits under the radio.

var _hum: AudioStreamPlayer
var _whine: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _built := false
var muted := false
var engine_kind := "jet"
var _thr := 0.0
var _spd := 0.0

const RATE := 22050


func build() -> void:
	if _built:
		return
	_hum = _player(_make_hum(), -16.0)
	_whine = _player(_make_noise(1400.0, 0.985), -30.0)
	_wind = _player(_make_noise(420.0, 0.9), -40.0)
	_built = true


func _player(stream: AudioStreamWAV, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.bus = "Master"
	add_child(p)
	p.play()
	return p


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = samples.size()
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v := int(clamp(samples[i], -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, v)
	w.data = data
	return w


## Low turbine hum: a few harmonics of a base note, one second long so the
## loop point lands on a whole cycle.
func _make_hum() -> AudioStreamWAV:
	var n := RATE
	var out := PackedFloat32Array()
	out.resize(n)
	var base := 62.0
	for i in range(n):
		var t := float(i) / RATE
		var v := 0.0
		for h in range(1, 7):
			v += sin(TAU * base * h * t) / float(h * h) * (1.0 if h % 2 == 1 else 0.6)
		# Slow beat between two detuned fundamentals reads as a real engine.
		v += 0.5 * sin(TAU * base * 1.0 * t) * sin(TAU * 2.0 * t)
		out[i] = v * 0.45
	return _wav(out)


## Band-passed white noise (2-pole resonator). `r` close to 1 = narrow band.
func _make_noise(freq: float, r: float) -> AudioStreamWAV:
	var n := RATE * 2
	var out := PackedFloat32Array()
	out.resize(n)
	var y1 := 0.0
	var y2 := 0.0
	var w := TAU * freq / RATE
	var a1 := 2.0 * r * cos(w)
	var a2 := -r * r
	var gain := (1.0 - r) * 2.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var peak := 0.0001
	for i in range(n):
		var x := rng.randf_range(-1.0, 1.0)
		var y := x * gain + a1 * y1 + a2 * y2
		y2 = y1
		y1 = y
		out[i] = y
		peak = max(peak, abs(y))
	for i in range(n):
		out[i] = out[i] / peak * 0.8
	# Fade the loop ends into each other.
	var f := 2000
	for i in range(f):
		var k := float(i) / f
		out[i] = out[i] * k + out[n - f + i] * (1.0 - k)
	return _wav(out)


func update(throttle: float, airspeed: float, delta: float) -> void:
	if not _built:
		return
	_thr = lerp(_thr, throttle, 1.0 - exp(-delta * 1.5))
	_spd = lerp(_spd, airspeed, 1.0 - exp(-delta * 2.0))
	var m := muted
	var base_pitch := 0.7
	var hum_db := -17.0
	match engine_kind:
		"afterburner":
			base_pitch = 0.6
			hum_db = -15.0
		"ion":
			base_pitch = 1.6
			hum_db = -20.0
	_hum.pitch_scale = base_pitch + _thr * 0.9
	_hum.volume_db = (hum_db + _thr * 6.0) if not m else -80.0
	_whine.pitch_scale = 0.6 + _thr * 1.2
	_whine.volume_db = (-34.0 + _thr * 12.0) if not m else -80.0
	var wind: float = clamp((_spd - 40.0) / 260.0, 0.0, 1.0)
	_wind.pitch_scale = 0.7 + wind * 0.9
	_wind.volume_db = (-42.0 + wind * 24.0) if not m else -80.0
