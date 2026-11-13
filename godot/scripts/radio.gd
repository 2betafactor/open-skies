extends Node
class_name Radio
## Nightride FM — the synthwave stream the original game plays under flight.
##
## Web export: an HTML <audio> element via JavaScriptBridge (gapless, cheap).
## Native: the MP3 stream is pulled over HTTP in chunks and each chunk is
## decoded by AudioStreamMP3; chunks are chained on `finished`, so native
## playback has a faint seam every ~20 s — good enough for a desktop build.

const STREAM_URL := "https://stream.nightride.fm/nightride.mp3"
const NAME := "Nightride FM"

var playing := false
var status := "Nightride FM starts with takeoff. M toggles."
var volume_db := -6.0

# native streaming
var _http: HTTPClient
var _buf := PackedByteArray()
var _players: Array[AudioStreamPlayer] = []
var _pending: Array[PackedByteArray] = []
var _connected := false
var _chunk_bytes := 20 * 16000     # ~20 s at 128 kbps

signal status_changed(text: String)


func _ready() -> void:
	if not OS.has_feature("web"):
		for i in range(2):
			var p := AudioStreamPlayer.new()
			p.volume_db = volume_db
			add_child(p)
			p.finished.connect(_on_player_finished)
			_players.append(p)


func toggle() -> void:
	if playing:
		stop()
	else:
		play()


func play() -> void:
	playing = true
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""
			(function(){
				if (!window.__osRadio) { window.__osRadio = new Audio(); window.__osRadio.crossOrigin = 'anonymous'; window.__osRadio.preload = 'none'; }
				var a = window.__osRadio; a.src = '%s'; a.volume = %f;
				a.play().then(function(){ window.__osRadioState = 'playing'; }).catch(function(e){ window.__osRadioState = 'blocked:' + e; });
			})();
		""" % [STREAM_URL, db_to_linear(volume_db)], true)
		_set_status("Playing %s." % NAME)
	else:
		_set_status("Connecting to %s…" % NAME)
		_start_native()


func stop() -> void:
	playing = false
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if (window.__osRadio) { window.__osRadio.pause(); window.__osRadio.src=''; }", true)
	else:
		for p in _players:
			p.stop()
		_pending.clear()
		_buf = PackedByteArray()
		_http = null
		_connected = false
	_set_status("Radio off. M to turn it on.")


func set_volume(db: float) -> void:
	volume_db = db
	for p in _players:
		p.volume_db = db
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if (window.__osRadio) window.__osRadio.volume = %f;" % db_to_linear(db), true)


func _set_status(t: String) -> void:
	status = t
	status_changed.emit(t)


# ----------------------------------------------------------------- native

func _start_native() -> void:
	_http = HTTPClient.new()
	var err := _http.connect_to_host("https://stream.nightride.fm", 443)
	if err != OK:
		_set_status("%s could not be reached." % NAME)
		playing = false
		_http = null


func _process(_delta: float) -> void:
	if OS.has_feature("web"):
		if playing and Engine.get_process_frames() % 120 == 0:
			var st = JavaScriptBridge.eval("window.__osRadioState || ''", true)
			if st is String and st.begins_with("blocked"):
				_set_status("Click or press a key to allow audio, then press M.")
		return
	if _http == null:
		return
	_http.poll()
	var st := _http.get_status()
	if not _connected:
		if st == HTTPClient.STATUS_CONNECTED:
			_http.request(HTTPClient.METHOD_GET, "/nightride.mp3", PackedStringArray(["Icy-MetaData: 0", "Accept: */*"]))
			_connected = true
		elif st == HTTPClient.STATUS_CANT_CONNECT or st == HTTPClient.STATUS_CANT_RESOLVE or st == HTTPClient.STATUS_CONNECTION_ERROR or st == HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			_set_status("%s could not be reached." % NAME)
			_http = null
			playing = false
		return
	if st == HTTPClient.STATUS_BODY:
		var chunk := _http.read_response_body_chunk()
		if chunk.size() > 0:
			_buf.append_array(chunk)
			if _buf.size() >= _chunk_bytes:
				_pending.append(_buf)
				_buf = PackedByteArray()
				_feed()
	elif st != HTTPClient.STATUS_REQUESTING and st != HTTPClient.STATUS_CONNECTED:
		_set_status("%s stream ended." % NAME)
		_http = null


func _feed() -> void:
	# Start playback once we have a chunk and nothing is playing.
	for p in _players:
		if p.playing:
			return
	_play_next(_players[0])


func _play_next(p: AudioStreamPlayer) -> void:
	if _pending.is_empty():
		return
	var data: PackedByteArray = _pending.pop_front()
	var mp3 := AudioStreamMP3.new()
	mp3.data = data
	p.stream = mp3
	p.play()
	_set_status("Playing %s." % NAME)


func _on_player_finished() -> void:
	for p in _players:
		if not p.playing:
			_play_next(p)
			return
