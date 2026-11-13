extends Node3D
## Open Skies — app state machine and scene wiring.
##
## MENU -> PREPARING (origin set, tiles stream, wait for ground under the
## spawn) -> FLYING <-> PAUSED; FLYING -> CRASHED -> respawn; FLYING ->
## FINISHED (score posted) -> MENU.

enum State { BOOT, MENU, PREPARING, FLYING, PAUSED, CRASHED, FINISHED }

const PRESETS := [
	{"name": "San Francisco", "lat": 37.7897, "lon": -122.4017},
	{"name": "New York", "lat": 40.7484, "lon": -73.9857},
	{"name": "Paris", "lat": 48.8584, "lon": 2.2945},
	{"name": "London", "lat": 51.5007, "lon": -0.1246},
	{"name": "Tokyo", "lat": 35.6586, "lon": 139.7454},
	{"name": "Dubai", "lat": 25.1972, "lon": 55.2744},
	{"name": "Rio de Janeiro", "lat": -22.9519, "lon": -43.2105},
	{"name": "Sydney", "lat": -33.8568, "lon": 151.2153},
	{"name": "Rome", "lat": 41.8902, "lon": 12.4922},
	{"name": "Hong Kong", "lat": 22.2793, "lon": 114.1628},
	{"name": "Barcelona", "lat": 41.4036, "lon": 2.1744},
	{"name": "Chicago", "lat": 41.8781, "lon": -87.6298},
]

const QUALITY := {
	"Performance": {"sse": 44.0, "far": 60000.0, "msaa": Viewport.MSAA_DISABLED, "tiles": 600, "scale": 0.75, "preload": 3500.0},
	"Balanced": {"sse": 26.0, "far": 90000.0, "msaa": Viewport.MSAA_DISABLED, "tiles": 1000, "scale": 1.0, "preload": 5000.0},
	"Quality": {"sse": 15.0, "far": 120000.0, "msaa": Viewport.MSAA_2X, "tiles": 1600, "scale": 1.0, "preload": 6500.0},
}

var state := State.BOOT
var tiles: GoogleTiles
var aircraft: Aircraft
var camera: FlightCamera
var hud: Hud
var rings: RingCourse
var touch: TouchControls
var is_mobile := false
var menu: Node
var engine_audio: EngineAudio
var radio: Radio
var env: WorldEnvironment
var sun: DirectionalLight3D

var place := {"name": "San Francisco", "lat": 37.7897, "lon": -122.4017}
var vehicle_id := "typhoon"
var quality := "Balanced"
var radio_wanted := true
var rings_wanted := true
var _prep_timer := 0.0
var _crash_timer := 0.0
var _path: Array = []
var _path_timer := 0.0
var top_speed := 0.0
var _tiles_started := false
var last_result: Dictionary = {}
var _rebase_count := 0


func _ready() -> void:
	_build_environment()
	tiles = GoogleTiles.new()
	tiles.name = "Tiles"
	add_child(tiles)
	aircraft = Aircraft.new()
	aircraft.name = "Aircraft"
	aircraft.tiles = tiles
	aircraft.crashed.connect(_on_crashed)
	aircraft.maneuver_done.connect(_on_maneuver_done)
	add_child(aircraft)
	camera = FlightCamera.new()
	camera.name = "Camera"
	camera.target = aircraft
	add_child(camera)
	tiles.camera = camera
	tiles.focus = aircraft
	engine_audio = EngineAudio.new()
	add_child(engine_audio)
	radio = Radio.new()
	add_child(radio)
	hud = Hud.new()
	hud.aircraft = aircraft
	hud.tiles = tiles
	hud.camera = camera
	hud.radio = radio
	add_child(hud)
	hud.visible = false
	rings = RingCourse.new()
	rings.aircraft = aircraft
	rings.tiles = tiles
	rings.ring_passed.connect(_on_ring_passed)
	rings.ring_missed.connect(func(): hud.toast("Missed", 0.8))
	add_child(rings)
	hud.rings = rings
	touch = TouchControls.new()
	touch.main = self
	add_child(touch)
	is_mobile = _detect_mobile()
	_apply_ui_scale()
	get_viewport().size_changed.connect(_apply_ui_scale)
	menu = load("res://scripts/menu.gd").new()
	menu.main = self
	add_child(menu)
	_expose_debug()
	_boot()


## Phones/tablets: touchscreen present, or a mobile user agent on the web.
func _detect_mobile() -> bool:
	if _url_param("touch") == "1":
		return true
	if _url_param("touch") == "0":
		return false
	if DisplayServer.is_touchscreen_available():
		return true
	if OS.has_feature("web"):
		var ua = JavaScriptBridge.eval("/Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent) || (navigator.maxTouchPoints || 0) > 1", true)
		return ua == true
	return false


## Scale the UI with the screen: readable on a phone, not gigantic on a 4K
## monitor. The project renders at the window's real resolution.
func _apply_ui_scale() -> void:
	var sz := get_viewport().get_visible_rect().size
	var short_side: float = min(sz.x, sz.y)
	var factor: float = clamp(short_side / 720.0, 0.75, 2.0)
	if is_mobile:
		factor = clamp(short_side / 420.0, 1.0, 2.6)
	get_tree().root.content_scale_factor = factor
	if menu != null:
		menu.relayout()
	if hud != null:
		hud.mobile = is_mobile


func _boot() -> void:
	state = State.MENU
	if is_mobile:
		quality = "Performance"
		menu.set_mobile_defaults()
	menu.set_status("Loading configuration…")
	await Api.load_config()
	if Api.api_key == "":
		menu.set_status("No Google Maps API key. Put it in config.js (or GOOGLE_MAPS_API_KEY) and restart the server.", true)
	else:
		menu.set_status("")
		tiles.start(Api.api_key)
		_tiles_started = true
	menu.refresh_scores()
	if _url_param("autostart") == "1":
		menu._on_take_off()


var _trace_timer := 0.0
var _trace_total := 0.0


func _trace(delta: float) -> void:
	if _url_param("trace") != "1":
		return
	_trace_timer += delta
	_trace_total += delta
	var limit := _url_param("seconds")
	if limit != "" and _trace_total > float(limit):
		var shot := _url_param("shot")
		if shot != "":
			var img := get_viewport().get_texture().get_image()
			img.save_png(shot)
			print("[trace] screenshot ", shot, " ", img.get_size())
		print("[trace] done")
		get_tree().quit()
	if _trace_timer >= 3.0:
		_trace_timer = 0.0
		var st := tiles.stats()
		var g := tiles.ground_height(aircraft.position)
		var tm := aircraft.telemetry()
		pass
		print("[trace] state=%s tiles(vis=%d loaded=%d q=%d dec=%d avg=%.1fms fail=%d) ground=%s agl=%s alt=%.0f spd=%.0f pos=%s" % [State.keys()[state], st.visible, st.loaded, st.queued, st.pending_decode, st.decode_ms_avg, st.failed, str(g), str(tm.agl), tm.altitude, tm.airspeed, aircraft.position.snapped(Vector3(1, 1, 1))])


func _build_environment() -> void:
	env = WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.22, 0.42, 0.78)
	mat.sky_horizon_color = Color(0.86, 0.72, 0.58)
	mat.ground_bottom_color = Color(0.25, 0.22, 0.2)
	mat.ground_horizon_color = Color(0.84, 0.7, 0.56)
	mat.sun_angle_max = 18.0
	mat.sun_curve = 0.12
	mat.sky_energy_multiplier = 1.0
	sky.sky_material = mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_light_color = Color(0.82, 0.74, 0.66)
	e.fog_light_energy = 1.0
	e.fog_density = 0.000016
	e.fog_sky_affect = 0.35
	e.fog_aerial_perspective = 0.6
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.08
	e.adjustment_contrast = 1.03
	env.environment = e
	add_child(env)
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.88, 0.72)
	sun.light_energy = 1.4
	sun.rotation_degrees = Vector3(-28.0, 140.0, 0.0)
	# Shadows only matter on the aircraft (tiles are unshaded), so keep the
	# shadow volume tight around it: orthogonal, short range, one split.
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_fade_start = 0.9
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.5
	add_child(sun)


# ------------------------------------------------------------------- flow

func start_flight() -> void:
	if Api.api_key == "" or not _tiles_started:
		menu.set_status("Tiles are not available without an API key.", true)
		return
	_apply_quality()
	Geo.set_origin(place.lat, place.lon, 0.0)
	aircraft.set_vehicle(vehicle_id)
	engine_audio.engine_kind = aircraft.spec.engine
	engine_audio.build()
	# Spawn 2.5 km out, pointed at the place, so the city is in front of you.
	var heading := randf_range(0.0, 360.0)
	var back := Geo.geodetic_to_local(place.lat, place.lon, 0.0) - Vector3(sin(deg_to_rad(heading)), 0.0, -cos(deg_to_rad(heading))) * 2500.0
	var spawn_geo := Geo.local_to_geodetic(back)
	aircraft.spawn(spawn_geo[0], spawn_geo[1], 700.0, heading)
	aircraft.frozen = true
	camera.set_mode(FlightCamera.Mode.CHASE)
	camera.snap()
	hud.place_name = place.name
	hud.visible = true
	menu.show_loading(true)
	menu.hide_menu()
	_path.clear()
	top_speed = 0.0
	_prep_timer = 0.0
	# Preload a full bubble around the spawn so the first minute is smooth.
	tiles.preload_radius = float(QUALITY.get(quality, QUALITY["Balanced"]).get("preload", 5000.0))
	if is_mobile:
		tiles.preload_radius = min(tiles.preload_radius, 3000.0)
	if _url_param("preload") != "":
		tiles.preload_radius = float(_url_param("preload"))
	touch.set_enabled(is_mobile)
	state = State.PREPARING
	_set_mouse_capture(false)


func _apply_quality() -> void:
	var q: Dictionary = QUALITY.get(quality, QUALITY["Balanced"])
	tiles.max_sse = q.sse
	tiles.far_distance = q.far
	tiles.max_loaded_tiles = q.tiles
	camera.far = q.far + 30000.0
	get_viewport().msaa_3d = q.msaa
	var scale: float = q.scale
	var override := _url_param("scale")
	if override != "":
		scale = clamp(float(override), 0.2, 1.0)
	get_viewport().scaling_3d_scale = scale


## Query-string overrides on the web build (tests / weak machines):
## ?quality=Performance&scale=0.5
func _url_param(name: String) -> String:
	if not OS.has_feature("web"):
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--%s=" % name):
				return a.substr(name.length() + 3)
		return ""
	var v = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('%s') || ''" % name, true)
	return str(v) if v != null else ""


func _finish_preparing() -> void:
	tiles.preload_radius = 0.0
	# Lift the spawn so we start a safe height above whatever is below.
	var g := tiles.ground_height(aircraft.position)
	if not is_nan(g):
		aircraft.position.y = g + 650.0
	aircraft.frozen = false
	aircraft.alive = true
	camera.snap()
	menu.show_loading(false)
	state = State.FLYING
	if radio_wanted:
		radio.play()
	if rings_wanted:
		rings.start()
	if is_mobile:
		hud.show_hint("Drag on the left to steer · right slider boosts or brakes · buttons along the bottom", 10.0)
		return
	hud.show_hint("W/S pitch · A/D roll · Q/E rudder · Shift/Ctrl throttle · L level · R loop · T roll · C camera · B assist · Esc menu", 12.0)


func pause() -> void:
	if state != State.FLYING:
		return
	state = State.PAUSED
	aircraft.frozen = true
	menu.show_pause(true)


func resume() -> void:
	if state != State.PAUSED:
		return
	state = State.FLYING
	aircraft.frozen = false
	menu.show_pause(false)


func finish_flight() -> void:
	if state != State.FLYING and state != State.PAUSED and state != State.CRASHED:
		return
	state = State.FINISHED
	aircraft.frozen = true
	menu.show_pause(false)
	var tm := aircraft.telemetry()
	var vehicle_api: String = {"typhoon": "cyberwing", "tomcat": "plane", "sabre": "plane", "nova": "spaceship"}.get(vehicle_id, "plane")
	var entry := {
		"name": menu.pilot_name(),
		"distanceKm": tm.distance / 1000.0,
		"timeSec": tm.time,
		"topSpeedKmh": top_speed * 3.6,
		"path": _path.slice(0, 800),
		"vehicle": vehicle_api,
		"world": "google",
	}
	last_result = {"distance": tm.distance, "time": tm.time, "max_g": aircraft.max_g, "top_speed": top_speed, "place": place.name, "score": rings.score, "rings": rings.rings_hit, "best_combo": rings.best_combo}
	rings.clear()
	menu.show_summary(last_result, null)
	var res = await Api.submit_score(entry)
	if res is Dictionary:
		menu.show_summary(last_result, res.get("board", []))
	else:
		menu.show_summary(last_result, [])


func back_to_menu() -> void:
	state = State.MENU
	aircraft.frozen = true
	rings.clear()
	touch.set_enabled(false)
	hud.visible = false
	radio.stop()
	menu.show_pause(false)
	menu.show_loading(false)
	menu.show_menu()
	_set_mouse_capture(false)


func _on_crashed() -> void:
	if state != State.FLYING:
		return
	state = State.CRASHED
	_crash_timer = 3.0
	camera.kick(6.0)
	hud.toast("Impact. Respawning…", 3.0)


func _respawn() -> void:
	var geo := aircraft.geodetic()
	var g := tiles.ground_height(aircraft.position)
	var alt: float = (g if not is_nan(g) else aircraft.position.y) + 500.0
	var dist := aircraft.distance_m
	var ft := aircraft.flight_time
	var mg := aircraft.max_g
	aircraft.spawn(geo[0], geo[1], alt, aircraft.heading_deg())
	aircraft.distance_m = dist
	aircraft.flight_time = ft
	aircraft.max_g = mg
	aircraft.frozen = false
	camera.snap()
	state = State.FLYING


func _on_maneuver_done(kind: String) -> void:
	if kind == "loop":
		rings.score += 500
		hud.toast("LOOP  +500", 2.0)
	elif kind == "roll":
		rings.score += 300
		hud.toast("BARREL ROLL  +300", 2.0)


func _on_ring_passed(points: int, combo: int) -> void:
	hud.toast("+%d%s" % [points, ("  x%d combo" % combo) if combo > 1 else ""], 1.2)
	camera.kick(0.6)


# --------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	_trace(delta)
	match state:
		State.PREPARING:
			_prep_timer += delta
			var progress := tiles.loading_progress()
			var g := tiles.ground_height(aircraft.position)
			var st := tiles.stats()
			menu.set_loading(progress, "Loading %s… %d%% (%d tiles)" % [place.name, int(progress * 100.0), st.loaded])
			# Go once the whole preload bubble is in (queue idle) and we know
			# the ground height under the spawn; never wait longer than ~45 s.
			var done: bool = tiles.idle() and _prep_timer > 1.5 and (not is_nan(g) or _prep_timer > 10.0)
			if done or _prep_timer > 45.0:
				_finish_preparing()
		State.FLYING, State.CRASHED:
			_flying(delta)
	if state == State.CRASHED:
		_crash_timer -= delta
		if _crash_timer <= 0.0:
			_respawn()
	if state != State.MENU and state != State.BOOT:
		engine_audio.update(aircraft.throttle if aircraft.alive else 0.0, aircraft.airspeed, delta)


func _flying(delta: float) -> void:
	top_speed = max(top_speed, aircraft.airspeed)
	tiles.lookahead_velocity = aircraft.velocity
	_path_timer -= delta
	if _path_timer <= 0.0:
		_path_timer = 2.0
		var geo := aircraft.geodetic()
		_path.append([snapped(geo[1], 0.00001), snapped(geo[0], 0.00001), int(geo[2]), int(aircraft.flight_time)])
		if _path.size() > 800:
			_path.pop_front()
	# Floating origin: keep the scene near the aircraft.
	if aircraft.position.length() > 25000.0:
		_rebase()


func _rebase() -> void:
	var old_basis := Geo.ecef_basis()
	var ecef := Geo.local_to_ecef(aircraft.position)
	var geo := Geo.ecef_to_geodetic(ecef[0], ecef[1], ecef[2])
	var cam_ecef := Geo.local_to_ecef(camera.global_position)
	Geo.set_origin(geo[0], geo[1], 0.0)
	var new_basis := Geo.ecef_basis()
	var rot: Basis = new_basis * old_basis.inverse()
	aircraft.rebase(Geo.ecef_arr_to_local(ecef), rot)
	camera.global_position = Geo.ecef_arr_to_local(cam_ecef)
	camera.global_basis = (rot * camera.global_basis).orthonormalized()
	_rebase_count += 1


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("menu"):
			match state:
				State.FLYING:
					pause()
				State.PAUSED:
					resume()
			return
		if state != State.FLYING:
			return
		if event.is_action_pressed("camera"):
			camera.cycle_mode()
			hud.toast(camera.MODE_NAMES[camera.mode] + " camera", 1.5)
		elif event.is_action_pressed("assist"):
			aircraft.cycle_assist()
			hud.toast("Assist: " + Aircraft.ASSIST_NAMES[aircraft.assist], 1.5)
		elif event.is_action_pressed("level"):
			aircraft.level_out()
		elif event.is_action_pressed("loop"):
			aircraft.start_maneuver("loop")
		elif event.is_action_pressed("barrel_roll"):
			aircraft.start_maneuver("roll")
		elif event.is_action_pressed("hud"):
			hud.compact = not hud.compact
		elif event.is_action_pressed("radio"):
			radio.toggle()


func _set_mouse_capture(_on: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ----------------------------------------------------------------- debug

## Exposes a snapshot for browser-side tests (window.openskies()).
func _expose_debug() -> void:
	if not OS.has_feature("web"):
		return
	_debug_cb = JavaScriptBridge.create_callback(_debug_snapshot)
	JavaScriptBridge.get_interface("window").openskies_cb = _debug_cb
	JavaScriptBridge.eval("window.openskies = function(){ window.__os_snapshot = null; window.openskies_cb(); return window.__os_snapshot; };", true)
	_takeoff_cb = JavaScriptBridge.create_callback(_debug_takeoff)
	JavaScriptBridge.get_interface("window").openskies_takeoff = _takeoff_cb

var _debug_cb: JavaScriptObject
var _takeoff_cb: JavaScriptObject


func _debug_takeoff(_args: Array) -> void:
	if state == State.MENU:
		menu._on_take_off()


func _debug_snapshot(_args: Array) -> void:
	var st := tiles.stats()
	var tm := aircraft.telemetry() if aircraft else {}
	for k in tm.keys():
		if tm[k] is float and is_nan(tm[k]):
			tm[k] = null
	var snap := {
		"state": State.keys()[state],
		"tiles": st,
		"tiles_state": tiles.ready_state,
		"tiles_error": tiles.error_text,
		"fps": Engine.get_frames_per_second(),
		"telemetry": tm,
		"rebases": _rebase_count,
		"prep": _prep_timer,
		"ground": tiles.ground_height(aircraft.position) if aircraft and state != State.MENU else null,
	}
	if snap.ground is float and is_nan(snap.ground):
		snap.ground = null
	if state == State.FLYING or state == State.PREPARING:
		var dbg := tiles.debug_collision(aircraft.position)
		dbg.erase("sample")
		snap["collision"] = dbg
		snap["pos"] = [aircraft.position.x, aircraft.position.y, aircraft.position.z]
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(aircraft.position + Vector3(0, 2, 0), aircraft.position + Vector3(0, -6000, 0), 1)
		var hit := space.intersect_ray(q)
		snap["ray_from_aircraft"] = str(hit.get("position", "none"))
		snap["ground_check_err"] = aircraft.ground_check_err
		snap["physics"] = str(ProjectSettings.get_setting("physics/3d/physics_engine", "default"))
		var heights := {}
		for h in [12000.0, 3000.0, 1500.0, 900.0, aircraft.position.y + 2.0]:
			var q2 := PhysicsRayQueryParameters3D.create(Vector3(aircraft.position.x, h, aircraft.position.z), Vector3(aircraft.position.x, -1000.0, aircraft.position.z), 1)
			var h2 := space.intersect_ray(q2)
			heights[str(int(h))] = h2.position.y if h2.has("position") else null
		snap["ray_heights"] = heights
		snap["pos_after"] = [aircraft.position.x, aircraft.position.y, aircraft.position.z]
		snap["gpos_after"] = [aircraft.global_position.x, aircraft.global_position.y, aircraft.global_position.z]
		snap["origin_h"] = Geo.origin_h
		snap["alive"] = aircraft.alive
		snap["state_after"] = State.keys()[state]
	JavaScriptBridge.eval("window.__os_snapshot = " + JSON.stringify(snap) + ";", true)


func debug_snapshot_dict() -> Dictionary:
	return {"state": State.keys()[state], "tiles": tiles.stats(), "telemetry": aircraft.telemetry()}
