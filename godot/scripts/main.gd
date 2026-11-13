extends Node3D
## Open Skies — arcade ring run over Google's 3D world.
##
## MENU -> PREPARING (tiles stream in around the spawn) -> RUN (timed) ->
## TIME_UP (summary) -> RUN again / FREE (no timer) / MENU. Crashes cost
## time and respawn you a moment later.

enum State { BOOT, MENU, PREPARING, RUN, FREE, PAUSED, CRASHED, TIME_UP }

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
]

const QUALITY := {
	"Performance": {"sse": 46.0, "far": 45000.0, "msaa": Viewport.MSAA_DISABLED, "tiles": 450, "scale": 0.7, "preload": 1500.0},
	"Balanced": {"sse": 30.0, "far": 80000.0, "msaa": Viewport.MSAA_DISABLED, "tiles": 900, "scale": 1.0, "preload": 2000.0},
	"Quality": {"sse": 18.0, "far": 110000.0, "msaa": Viewport.MSAA_2X, "tiles": 1500, "scale": 1.0, "preload": 3000.0},
}

const RUN_SECONDS := 60.0
const RING_SECONDS := 4.0
const CRASH_PENALTY := 5.0

var state := State.BOOT
var tiles: GoogleTiles
var aircraft: Aircraft
var camera: FlightCamera
var hud: Hud
var menu: Node
var engine_audio: EngineAudio
var radio: Radio
var rings: RingCourse
var touch: TouchControls
var fx: Fx
var sfx: Sfx
var env: WorldEnvironment
var sun: DirectionalLight3D
var is_mobile := false

var place := {"name": "San Francisco", "lat": 37.7897, "lon": -122.4017}
var vehicle_id := "typhoon"
var quality := "Balanced"
var pilot_name := "PILOT"
var time_left := RUN_SECONDS
var top_speed := 0.0
var last_result: Dictionary = {}
var _prep_timer := 0.0
var _crash_timer := 0.0
var _tiles_started := false
var _rebase_count := 0
var _spawn_heading := 0.0
var _spawn_geo: Array = [0.0, 0.0]
var _resume_state := State.RUN
var _debug_cb: JavaScriptObject
var _takeoff_cb: JavaScriptObject
var _trace_timer := 0.0
var _trace_total := 0.0


func _ready() -> void:
	_build_environment()
	tiles = GoogleTiles.new()
	add_child(tiles)
	aircraft = Aircraft.new()
	aircraft.tiles = tiles
	aircraft.crashed.connect(_on_crashed)
	aircraft.maneuver_done.connect(_on_maneuver_done)
	add_child(aircraft)
	camera = FlightCamera.new()
	camera.target = aircraft
	add_child(camera)
	tiles.camera = camera
	tiles.focus = aircraft
	engine_audio = EngineAudio.new()
	add_child(engine_audio)
	sfx = Sfx.new()
	add_child(sfx)
	radio = Radio.new()
	add_child(radio)
	fx = Fx.new()
	add_child(fx)
	rings = RingCourse.new()
	rings.aircraft = aircraft
	rings.tiles = tiles
	rings.ring_passed.connect(_on_ring_passed)
	rings.ring_missed.connect(_on_ring_missed)
	add_child(rings)
	hud = Hud.new()
	hud.aircraft = aircraft
	hud.tiles = tiles
	hud.camera = camera
	hud.radio = radio
	hud.rings = rings
	add_child(hud)
	hud.visible = false
	touch = TouchControls.new()
	touch.main = self
	add_child(touch)
	menu = load("res://scripts/menu.gd").new()
	menu.main = self
	add_child(menu)
	is_mobile = _detect_mobile()
	_apply_ui_scale()
	get_viewport().size_changed.connect(_apply_ui_scale)
	_load_prefs()
	_expose_debug()
	_boot()


func _boot() -> void:
	state = State.MENU
	quality = "Performance" if is_mobile else "Balanced"
	var q := _url_param("quality")
	if q != "" and QUALITY.has(q):
		quality = q
	menu.set_status("Loading…")
	await Api.load_config()
	if Api.api_key == "":
		menu.set_status("No Google Maps API key configured on the server.", true)
	else:
		menu.set_status("")
		tiles.start(Api.api_key)
		_tiles_started = true
	menu.refresh_scores()
	if _url_param("autostart") == "1":
		start_flight()


func _build_environment() -> void:
	env = WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.18, 0.4, 0.85)
	mat.sky_horizon_color = Color(0.95, 0.75, 0.55)
	mat.ground_bottom_color = Color(0.25, 0.22, 0.2)
	mat.ground_horizon_color = Color(0.9, 0.72, 0.55)
	mat.sun_angle_max = 20.0
	mat.sun_curve = 0.1
	sky.sky_material = mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.9
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.1
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_light_color = Color(0.9, 0.78, 0.66)
	e.fog_density = 0.00002
	e.fog_sky_affect = 0.3
	e.fog_aerial_perspective = 0.7
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.18
	e.adjustment_contrast = 1.05
	env.environment = e
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.light_energy = 1.5
	sun.rotation_degrees = Vector3(-30.0, 140.0, 0.0)
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
	aircraft.assist = Aircraft.Assist.ARCADE
	engine_audio.engine_kind = aircraft.spec.engine
	engine_audio.build()
	sfx.build()
	fx.attach(aircraft)
	# Spawn 2 km out, pointed at the city.
	_spawn_heading = randf_range(0.0, 360.0)
	var back := Geo.geodetic_to_local(place.lat, place.lon, 0.0) - Vector3(sin(deg_to_rad(_spawn_heading)), 0.0, -cos(deg_to_rad(_spawn_heading))) * 2000.0
	_spawn_geo = Geo.local_to_geodetic(back)
	aircraft.spawn(_spawn_geo[0], _spawn_geo[1], 600.0, _spawn_heading)
	aircraft.frozen = true
	camera.set_mode(FlightCamera.Mode.CHASE)
	camera.snap()
	hud.place_name = place.name
	hud.visible = true
	hud.mobile = is_mobile
	menu.show_loading(true)
	menu.hide_menu()
	menu.hide_summary()
	top_speed = 0.0
	_prep_timer = 0.0
	tiles.preload_radius = float(QUALITY[quality].preload)
	if _url_param("preload") != "":
		tiles.preload_radius = float(_url_param("preload"))
	touch.set_enabled(is_mobile)
	state = State.PREPARING


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


func _begin_run() -> void:
	tiles.preload_radius = 0.0
	var g := tiles.ground_height(aircraft.position)
	if not is_nan(g):
		aircraft.position.y = g + 550.0
	aircraft.frozen = false
	aircraft.alive = true
	camera.snap()
	menu.show_loading(false)
	time_left = RUN_SECONDS
	hud.timed = true
	rings.start()
	state = State.RUN
	if not radio.playing:
		radio.play()
	sfx.play("combo", -10.0)
	if is_mobile:
		hud.show_hint("Drag left side to steer · right slider boosts / brakes · fly through the gold rings", 8.0)
	else:
		hud.show_hint("Arrows or WASD steer · hold SHIFT to boost · fly through the gold rings before time runs out", 8.0)


func restart_run() -> void:
	menu.show_pause(false)
	menu.hide_summary()
	aircraft.spawn(_spawn_geo[0], _spawn_geo[1], 600.0, _spawn_heading)
	var g := tiles.ground_height(aircraft.position)
	if not is_nan(g):
		aircraft.position.y = g + 550.0
	aircraft.frozen = false
	aircraft.alive = true
	aircraft.set_model_visible(camera.mode != FlightCamera.Mode.COCKPIT)
	camera.snap()
	top_speed = 0.0
	time_left = RUN_SECONDS
	hud.timed = true
	rings.start()
	state = State.RUN
	sfx.play("combo", -10.0)


func keep_flying() -> void:
	menu.hide_summary()
	hud.timed = false
	aircraft.frozen = false
	state = State.FREE
	hud.show_hint("Free flight — rings still score. Esc for the menu.", 5.0)


func pause() -> void:
	if state != State.RUN and state != State.FREE:
		return
	_resume_state = state
	state = State.PAUSED
	aircraft.frozen = true
	menu.show_pause(true)


func resume() -> void:
	if state != State.PAUSED:
		return
	state = _resume_state
	aircraft.frozen = false
	menu.show_pause(false)


func _time_up() -> void:
	state = State.TIME_UP
	aircraft.frozen = true
	sfx.play("miss", -8.0, 0.6)
	last_result = {"place": place.name, "score": rings.score, "rings": rings.rings_hit, "best_combo": rings.best_combo, "top_speed": top_speed, "time": aircraft.flight_time, "distance": aircraft.distance_m}
	menu.show_summary(last_result)


func post_score() -> void:
	pilot_name = menu.summary_name()
	_save_prefs()
	var vehicle_api: String = {"typhoon": "cyberwing", "tomcat": "plane", "sabre": "plane", "nova": "spaceship"}.get(vehicle_id, "plane")
	var entry := {
		"name": pilot_name,
		"score": int(last_result.score),
		"distanceKm": float(last_result.distance) / 1000.0,
		"timeSec": float(last_result.time),
		"topSpeedKmh": float(last_result.top_speed) * 3.6,
		"path": [],
		"vehicle": vehicle_api,
		"world": "google",
	}
	var res = await Api.submit_score(entry)
	menu.mark_posted(res is Dictionary)
	menu.refresh_scores()


func back_to_menu() -> void:
	state = State.MENU
	aircraft.frozen = true
	hud.visible = false
	rings.clear()
	touch.set_enabled(false)
	menu.show_pause(false)
	menu.show_loading(false)
	menu.hide_summary()
	menu.show_menu()
	menu.refresh_scores()


func _on_crashed() -> void:
	if state != State.RUN and state != State.FREE:
		return
	_resume_state = state
	state = State.CRASHED
	_crash_timer = 1.6
	camera.kick(8.0)
	fx.explode(aircraft.position)
	sfx.play("boom", -4.0)
	hud.flash(Color(1.0, 0.4, 0.2), 0.8)
	if _resume_state == State.RUN:
		time_left = max(time_left - CRASH_PENALTY, 0.0)
		hud.pop("CRASH  -%d s" % int(CRASH_PENALTY), true, Hud.COL_RED)
	rings.combo = 0
	aircraft.set_model_visible(false)


func _respawn() -> void:
	var geo := aircraft.geodetic()
	var g := tiles.ground_height(aircraft.position)
	var alt: float = (g if not is_nan(g) else aircraft.position.y) + 450.0
	var dist := aircraft.distance_m
	var ft := aircraft.flight_time
	aircraft.spawn(geo[0], geo[1], alt, aircraft.heading_deg())
	aircraft.distance_m = dist
	aircraft.flight_time = ft
	aircraft.frozen = false
	aircraft.set_model_visible(camera.mode != FlightCamera.Mode.COCKPIT)
	camera.snap()
	state = _resume_state


func _on_maneuver_done(kind: String) -> void:
	if kind == "level":
		return
	var pts := 500 if kind == "loop" else 300
	rings.score += pts
	hud.pop("%s  +%d" % ["LOOP" if kind == "loop" else "BARREL ROLL", pts], true)
	sfx.play("trick", -6.0)
	if state == State.RUN:
		time_left += 2.0


func _on_ring_passed(points: int, combo: int) -> void:
	hud.pop("+%d" % points, combo >= 3)
	hud.flash(Hud.COL_GOLD, 0.35)
	hud.combo_pulse()
	camera.kick(0.8)
	fx.burst(rings.last_hit_position, combo >= 5)
	sfx.play("ring_hi" if combo >= 5 else "ring", -6.0, 1.0 + min(combo, 8) * 0.04)
	if combo > 1 and combo % 5 == 0:
		sfx.play("combo", -8.0)
	if state == State.RUN:
		var bonus: float = RING_SECONDS + min(combo, 6) * 0.5
		time_left += bonus
		hud.pop("+%.1f s" % bonus, false, Hud.COL)


func _on_ring_missed() -> void:
	sfx.play("miss", -14.0)
	hud.pop("MISS", false, Hud.COL_RED)


# --------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	_trace(delta)
	match state:
		State.PREPARING:
			_prep_timer += delta
			var progress := tiles.loading_progress()
			var g := tiles.ground_height(aircraft.position)
			menu.set_loading(progress, "Streaming %s… %d%%" % [place.name, int(progress * 100.0)])
			var done: bool = tiles.idle() and _prep_timer > 1.0 and (not is_nan(g) or _prep_timer > 8.0)
			if done or _prep_timer > 30.0:
				_begin_run()
		State.RUN:
			_flying()
			time_left -= delta
			hud.time_left = time_left
			if time_left <= 0.0:
				time_left = 0.0
				_time_up()
		State.FREE:
			_flying()
		State.CRASHED:
			_crash_timer -= delta
			if _crash_timer <= 0.0:
				_respawn()
	if state != State.MENU and state != State.BOOT:
		engine_audio.update(aircraft.throttle if aircraft.alive else 0.0, aircraft.airspeed, delta)


func _flying() -> void:
	top_speed = max(top_speed, aircraft.airspeed)
	tiles.lookahead_velocity = aircraft.velocity
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
	rings.clear()
	if state == State.RUN or state == State.FREE:
		rings.start()
	_rebase_count += 1


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("menu"):
			match state:
				State.RUN, State.FREE:
					pause()
				State.PAUSED:
					resume()
				State.TIME_UP:
					back_to_menu()
			return
		if state != State.RUN and state != State.FREE:
			return
		if event.is_action_pressed("camera"):
			camera.cycle_mode()
		elif event.is_action_pressed("level"):
			aircraft.level_out()
		elif event.is_action_pressed("loop"):
			aircraft.start_maneuver("loop")
		elif event.is_action_pressed("barrel_roll"):
			aircraft.start_maneuver("roll")
		elif event.is_action_pressed("radio"):
			radio.toggle()


# ------------------------------------------------------------ platform

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


func _url_param(name: String) -> String:
	if not OS.has_feature("web"):
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--%s=" % name):
				return a.substr(name.length() + 3)
		return ""
	var v = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('%s') || ''" % name, true)
	return str(v) if v != null else ""


func _load_prefs() -> void:
	var f := FileAccess.open("user://prefs.json", FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			pilot_name = str(d.get("name", pilot_name))


func _save_prefs() -> void:
	var f := FileAccess.open("user://prefs.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"name": pilot_name}))


# ----------------------------------------------------------------- debug

func _expose_debug() -> void:
	if not OS.has_feature("web"):
		return
	_debug_cb = JavaScriptBridge.create_callback(_debug_snapshot)
	JavaScriptBridge.get_interface("window").openskies_cb = _debug_cb
	JavaScriptBridge.eval("window.openskies = function(){ window.__os_snapshot = null; window.openskies_cb(); return window.__os_snapshot; };", true)
	_takeoff_cb = JavaScriptBridge.create_callback(_debug_takeoff)
	JavaScriptBridge.get_interface("window").openskies_takeoff = _takeoff_cb


func _debug_takeoff(_args: Array) -> void:
	if state == State.MENU:
		start_flight()


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
		"score": rings.score,
		"time_left": time_left,
		"pos": [aircraft.position.x, aircraft.position.y, aircraft.position.z],
	}
	JavaScriptBridge.eval("window.__os_snapshot = " + JSON.stringify(snap) + ";", true)


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
		print("[trace] state=%s tiles(vis=%d loaded=%d q=%d dec=%d avg=%.1fms fail=%d) ground=%s agl=%s alt=%.0f spd=%.0f score=%d time=%.0f pos=%s" % [State.keys()[state], st.visible, st.loaded, st.queued, st.pending_decode, st.decode_ms_avg, st.failed, str(g), str(tm.agl), tm.altitude, tm.airspeed, rings.score, time_left, aircraft.position.snapped(Vector3(1, 1, 1))])
