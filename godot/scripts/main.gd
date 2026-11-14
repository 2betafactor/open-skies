extends Node3D
## Open Skies — arcade dogfight over Google's 3D world.
##
## MENU -> PREPARING (tiles stream in around the spawn) -> RUN (shoot down
## waves of ships, three lives) -> GAME_OVER (summary, post score) -> RUN
## again / MENU. Getting shot down or crashing costs a life and respawns you.

enum State { BOOT, MENU, PREPARING, RUN, PAUSED, CRASHED, GAME_OVER }

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

const LIVES := 3
const COMBO_WINDOW := 6.0

var state := State.BOOT
var tiles: GoogleTiles
var aircraft: Aircraft
var camera: FlightCamera
var hud: Hud
var menu: Node
var engine_audio: EngineAudio
var radio: Radio
var enemies: Enemies
var guns: Guns
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
var score := 0
var combo := 1
var _combo_timer := 0.0
var _best_combo := 1
var lives := LIVES
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
	enemies = Enemies.new()
	enemies.aircraft = aircraft
	enemies.tiles = tiles
	enemies.fx = fx
	enemies.ship_killed.connect(_on_ship_killed)
	enemies.player_hit.connect(_on_player_hit)
	enemies.wave_cleared.connect(_on_wave_cleared)
	add_child(enemies)
	guns = Guns.new()
	guns.aircraft = aircraft
	guns.enemies = enemies
	guns.fx = fx
	guns.sfx = sfx
	guns.hit_ship.connect(_on_gun_hit)
	add_child(guns)
	hud = Hud.new()
	hud.aircraft = aircraft
	hud.tiles = tiles
	hud.camera = camera
	hud.radio = radio
	hud.enemies = enemies
	add_child(hud)
	hud.visible = false
	touch = TouchControls.new()
	touch.main = self
	add_child(touch)
	menu = load("res://scripts/menu.gd").new()
	menu.main = self
	add_child(menu)
	is_mobile = _detect_mobile()
	Controls.mouse_aim = not is_mobile
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
		aircraft.position.y = g + 500.0
	aircraft.frozen = false
	aircraft.alive = true
	camera.snap()
	menu.show_loading(false)
	_reset_run()
	state = State.RUN
	if not radio.playing:
		radio.play()
	sfx.play("wave", -10.0)
	hud.announce("WAVE 1", 2.5)
	if is_mobile:
		hud.show_hint("Drag anywhere to steer · FIRE and BOOST bottom right · shoot the ships, dodge their shots", 8.0)
	else:
		hud.show_hint("Steer with the mouse (or arrows / WASD) · SPACE or click to fire · hold SHIFT to boost · R loop · T roll", 9.0)


func _reset_run() -> void:
	score = 0
	combo = 1
	_combo_timer = 0.0
	_best_combo = 1
	lives = LIVES
	top_speed = 0.0
	hud.score = 0
	hud.combo = 1
	hud.lives = lives
	hud.wave = 1
	guns.reset()
	enemies.start()
	if _url_param("testkill") == "1":
		enemies.spawn_dummy(450.0)


func restart_run() -> void:
	menu.show_pause(false)
	menu.hide_summary()
	aircraft.spawn(_spawn_geo[0], _spawn_geo[1], 600.0, _spawn_heading)
	var g := tiles.ground_height(aircraft.position)
	if not is_nan(g):
		aircraft.position.y = g + 500.0
	aircraft.frozen = false
	aircraft.alive = true
	aircraft.set_model_visible(camera.mode != FlightCamera.Mode.COCKPIT)
	camera.snap()
	_reset_run()
	state = State.RUN
	sfx.play("wave", -10.0)
	hud.announce("WAVE 1", 2.5)


func pause() -> void:
	if state != State.RUN:
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


func _game_over() -> void:
	state = State.GAME_OVER
	aircraft.frozen = true
	guns.firing = false
	last_result = {"place": place.name, "score": score, "kills": enemies.kills, "wave": enemies.wave, "best_combo": _best_combo, "top_speed": top_speed, "time": aircraft.flight_time, "distance": aircraft.distance_m}
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
	enemies.clear()
	guns.reset()
	guns.firing = false
	touch.set_enabled(false)
	menu.show_pause(false)
	menu.show_loading(false)
	menu.hide_summary()
	menu.show_menu()
	menu.refresh_scores()


func _on_crashed() -> void:
	_lose_life("CRASHED")


func _on_player_hit(damage: float) -> void:
	if state != State.RUN or not aircraft.alive:
		return
	aircraft.hp -= damage
	hud.flash(Color(1.0, 0.2, 0.2), 0.45)
	camera.kick(1.5)
	sfx.play("hurt", -10.0)
	if aircraft.hp <= 0.0:
		aircraft.alive = false
		_lose_life("SHOT DOWN")


func _lose_life(why: String) -> void:
	if state != State.RUN:
		return
	_resume_state = state
	state = State.CRASHED
	lives -= 1
	hud.lives = lives
	_crash_timer = 1.8
	camera.kick(8.0)
	fx.explode(aircraft.position)
	sfx.play("boom", -4.0)
	hud.flash(Color(1.0, 0.4, 0.2), 0.8)
	hud.pop(why, true, Hud.COL_RED)
	combo = 1
	hud.combo = 1
	guns.firing = false
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
	if lives <= 0:
		_game_over()
		return
	state = State.RUN
	hud.announce("%d LI%s LEFT" % [lives, "FE" if lives == 1 else "VES"], 2.0)


func _on_maneuver_done(kind: String) -> void:
	if kind == "level" or state != State.RUN:
		return
	var pts := 500 if kind == "loop" else 300
	_add_score(pts)
	hud.pop("%s  +%d" % ["LOOP" if kind == "loop" else "BARREL ROLL", pts], true)
	sfx.play("trick", -6.0)


func _add_score(pts: int) -> void:
	score += pts
	hud.score = score


func _on_gun_hit(_ship: Dictionary, killed: bool) -> void:
	if not killed:
		hud.flash(Hud.COL_GOLD, 0.08)
		sfx.play("hit", -18.0)


func _on_ship_killed(pos: Vector3) -> void:
	if _combo_timer > 0.0:
		combo += 1
	else:
		combo = 1
	_combo_timer = COMBO_WINDOW
	_best_combo = max(_best_combo, combo)
	hud.combo = combo
	hud.combo_pulse()
	var pts: int = 100 * min(combo, 10)
	_add_score(pts)
	hud.pop("+%d" % pts, combo >= 3)
	hud.flash(Hud.COL_GOLD, 0.3)
	camera.kick(1.2)
	fx.explode(pos)
	sfx.play("kill", -6.0, 1.0 + min(combo, 8) * 0.04)
	sfx.play("boom", -14.0, 1.4)


func _on_wave_cleared(n: int) -> void:
	_add_score(500)
	hud.wave = n + 1
	hud.announce("WAVE %d" % (n + 1), 2.5)
	hud.pop("WAVE CLEAR  +500", true)
	sfx.play("wave", -8.0)
	aircraft.hp = min(aircraft.hp + 40.0, 100.0)


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
			guns.firing = (Controls.fire or _url_param("autofire") == "1") and aircraft.alive
			if _url_param("autoaim") == "1":
				_autoaim()
			if _combo_timer > 0.0:
				_combo_timer -= delta
				if _combo_timer <= 0.0:
					combo = 1
					hud.combo = 1
			aircraft.hp = min(aircraft.hp + delta * 2.0, 100.0)
		State.CRASHED:
			_crash_timer -= delta
			if _crash_timer <= 0.0:
				_respawn()
	if state != State.MENU and state != State.BOOT:
		engine_audio.update(aircraft.throttle if aircraft.alive else 0.0, aircraft.airspeed, delta)


## Test bot: steer at the nearest ship (used by the headless flow test).
func _autoaim() -> void:
	var s := enemies.nearest(aircraft.position, 6000.0)
	if s.is_empty():
		return
	var dist: float = s.pos.distance_to(aircraft.position)
	var lead: Vector3 = s.pos + s.vel * (dist / (Guns.SPEED + aircraft.airspeed))
	var local: Vector3 = aircraft.basis.inverse() * (lead - aircraft.position)
	var axes := Vector2(clamp(local.x / 120.0, -1.0, 1.0), -clamp(local.y / 120.0, -1.0, 1.0))
	if local.z > 0.0:
		axes.x = 1.0   # target behind: keep turning
	if not is_nan(aircraft.altitude_agl) and aircraft.altitude_agl < 200.0:
		axes.y = -1.0  # terrain: pull up first
	var thr := 0.0
	if dist > 1000.0:
		thr = 1.0
	Controls.set_touch(axes, thr)
	Controls.brake = dist < 300.0


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
	for sh in enemies.ships:
		sh.pos = rot * sh.pos
		sh.vel = rot * sh.vel
		sh.wp = rot * sh.wp
	_rebase_count += 1


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("menu"):
			match state:
				State.RUN:
					pause()
				State.PAUSED:
					resume()
				State.GAME_OVER:
					back_to_menu()
			return
		if state != State.RUN:
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
		"score": score,
		"kills": enemies.kills,
		"lives": lives,
		"enemies": enemies.ships.size(),
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
		print("[trace] state=%s tiles(vis=%d loaded=%d q=%d dec=%d avg=%.1fms fail=%d) ground=%s agl=%s alt=%.0f spd=%.0f score=%d kills=%d ships=%d lives=%d pos=%s" % [State.keys()[state], st.visible, st.loaded, st.queued, st.pending_decode, st.decode_ms_avg, st.failed, str(g), str(tm.agl), tm.altitude, tm.airspeed, score, enemies.kills, enemies.ships.size(), lives, aircraft.position.snapped(Vector3(1, 1, 1))])
