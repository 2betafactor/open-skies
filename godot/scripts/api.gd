extends Node
## Api — talks to the Open Skies Python server (config, place search, scores).
##
## On the web export the server is wherever the page was loaded from. Native
## builds default to the hosted game and can be pointed elsewhere with
## `--server=https://host` (or the OPENSKIES_SERVER env var).

const DEFAULT_SERVER := "https://spacewalk.exe.xyz"

var base_url := ""
var api_key := ""
var config_loaded := false

signal config_ready(ok: bool)


func _ready() -> void:
	base_url = _detect_base()


func _detect_base() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server="):
			return a.substr(9).rstrip("/")
	var env := OS.get_environment("OPENSKIES_SERVER")
	if env != "":
		return env.rstrip("/")
	if OS.has_feature("web"):
		var origin = JavaScriptBridge.eval("window.location.origin", true)
		if origin is String and origin != "":
			return origin
	return DEFAULT_SERVER


func load_config() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--key="):
			api_key = a.substr(6)
	if api_key == "":
		api_key = OS.get_environment("GOOGLE_MAPS_API_KEY")
	if api_key != "":
		config_loaded = true
		config_ready.emit(true)
		return
	var data = await get_json("/api/config")
	if data is Dictionary and data.has("key"):
		api_key = str(data.key)
	config_loaded = true
	config_ready.emit(api_key != "")


func get_json(path: String, method := HTTPClient.METHOD_GET, body := ""):
	var r := HTTPRequest.new()
	r.use_threads = false
	r.timeout = 20.0
	r.accept_gzip = not OS.has_feature("web")
	add_child(r)
	var headers := PackedStringArray(["Content-Type: application/json"]) if body != "" else PackedStringArray()
	var err := r.request(base_url + path, headers, method, body)
	if err != OK:
		r.queue_free()
		return null
	var res: Array = await r.request_completed
	r.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return null
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


## Geocode a free-text place. Returns [{name, lat, lon}] (possibly empty).
func search(query: String) -> Array:
	var data = await get_json("/api/search?q=" + query.uri_encode())
	if data is Dictionary and data.has("results"):
		return data.results
	return []


func top_scores() -> Array:
	var data = await get_json("/api/scores")
	return data if data is Array else []


func submit_score(entry: Dictionary):
	return await get_json("/api/scores", HTTPClient.METHOD_POST, JSON.stringify(entry))
