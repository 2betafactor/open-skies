extends Node
class_name Sfx
## Synthesised arcade sound effects (no audio files): ring chime, combo
## rise, boost whoosh, miss buzz, explosion. Built once at start-up.

const RATE := 22050
var _sounds: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var muted := false


func build() -> void:
	if not _sounds.is_empty():
		return
	_sounds["ring"] = _chime(880.0, 0.35)
	_sounds["ring_hi"] = _chime(1320.0, 0.4)
	_sounds["combo"] = _arp([660.0, 880.0, 1100.0, 1320.0], 0.09)
	_sounds["miss"] = _buzz(160.0, 0.3)
	_sounds["boost"] = _whoosh(0.9)
	_sounds["boom"] = _boom(1.4)
	_sounds["trick"] = _arp([523.0, 659.0, 784.0, 1046.0, 1318.0], 0.07)
	_sounds["click"] = _chime(1500.0, 0.08)
	for i in range(6):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)


func play(name: String, volume_db: float = -8.0, pitch: float = 1.0) -> void:
	if muted or not _sounds.has(name):
		return
	for p in _players:
		if not p.playing:
			p.stream = _sounds[name]
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return
	# All busy: steal the first.
	_players[0].stream = _sounds[name]
	_players[0].volume_db = volume_db
	_players[0].pitch_scale = pitch
	_players[0].play()


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clamp(samples[i], -1.0, 1.0) * 32000.0))
	w.data = data
	return w


func _env(t: float, dur: float, attack: float = 0.005) -> float:
	if t < attack:
		return t / attack
	return pow(1.0 - (t - attack) / max(dur - attack, 0.001), 2.2)


func _chime(freq: float, dur: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var v := sin(TAU * freq * t) + 0.5 * sin(TAU * freq * 2.0 * t) + 0.25 * sin(TAU * freq * 3.0 * t)
		out[i] = v * 0.45 * _env(t, dur)
	return _wav(out)


func _arp(freqs: Array, step: float) -> AudioStreamWAV:
	var dur := step * freqs.size() + 0.25
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var v := 0.0
		for k in range(freqs.size()):
			var t0: float = k * step
			if t >= t0:
				var lt: float = t - t0
				v += sin(TAU * float(freqs[k]) * lt) * _env(lt, 0.3) * 0.5
		out[i] = v * 0.6
	return _wav(out)


func _buzz(freq: float, dur: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var sq := 1.0 if fmod(t * freq, 1.0) < 0.5 else -1.0
		out[i] = sq * 0.25 * _env(t, dur, 0.01) * (1.0 if int(t * 12.0) % 2 == 0 else 0.5)
	return _wav(out)


func _whoosh(dur: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var y1 := 0.0
	var y2 := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var f: float = 300.0 + 2500.0 * pow(t / dur, 0.6)
		var r := 0.97
		var w := TAU * f / RATE
		var x := rng.randf_range(-1.0, 1.0)
		var y := x * (1.0 - r) * 2.0 + 2.0 * r * cos(w) * y1 - r * r * y2
		y2 = y1
		y1 = y
		out[i] = y * 0.8 * sin(PI * t / dur)
	return _wav(out)


func _boom(dur: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var lp := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		var cutoff: float = 0.02 + 0.3 * pow(1.0 - t / dur, 3.0)
		lp += (x - lp) * cutoff
		out[i] = (lp * 3.0 + 0.3 * sin(TAU * 45.0 * t) * pow(1.0 - t / dur, 2.0)) * _env(t, dur, 0.01)
	return _wav(out)
