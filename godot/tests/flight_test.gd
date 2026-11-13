extends Node3D
## Headless flight-model check (no tiles, no network).
## Run: godot --headless --path godot tests/flight_test.tscn -- [--vehicle=aerion] [--debug]

var ac: Aircraft
var t := 0.0
var phase := 0
var phase_t := 0.0
var vehicle := "aerion"
var fails := 0
var debug := false
var loop_started := 0.0
var fbw_checked := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--vehicle="): vehicle = a.substr(10)
		if a == "--debug": debug = true
	Geo.set_origin(37.79, -122.4, 0.0)
	ac = Aircraft.new()
	ac.vehicle_id = vehicle
	add_child(ac)
	ac.spawn(37.79, -122.4, 800.0, 90.0)
	ac.frozen = false
	ac.input_enabled = true
	Controls.set_touch(Vector2.ZERO, 0.0)
	print("vehicle ", vehicle, " heading ", snapped(ac.heading_deg(), 0.1), " pitch ", snapped(ac.pitch_deg(), 0.1), " bank ", snapped(ac.bank_deg(), 0.1))
	# Run 8x faster but keep the physics step at 1/60 s (time_scale stretches
	# the step, so raise the tick rate to compensate).
	Engine.time_scale = 8.0
	Engine.physics_ticks_per_second = 480
	Engine.max_physics_steps_per_frame = 64


func _since() -> float:
	return t - phase_t


func _next(label: String) -> void:
	_report(label)
	phase += 1
	phase_t = t


func _physics_process(delta: float) -> void:
	t += delta
	if debug and int(t) != int(t - delta) and t < 25.0:
		print("[%5.1f] %s | pitch %.1f alpha %.1f g %.2f bank %.1f | %s" % [t, ac.debug_line(), ac.pitch_deg(), rad_to_deg(ac.alpha), ac.g_load, ac.bank_deg(), JSON.stringify(ac.fbw_dbg)])
	match phase:
		0:
			if _since() > 20.0:
				_check(abs(ac.pitch_deg()) < 8.0, "pitch stays sane hands-off (%.1f)" % ac.pitch_deg())
				_check(ac.position.y > 500.0 and ac.position.y < 1100.0, "altitude held (%.0f)" % ac.position.y)
				_check(ac.airspeed > 80.0, "airspeed kept (%.0f)" % ac.airspeed)
				_check(abs(ac.g_load - 1.0) < 0.3, "about 1 G in level flight (%.2f)" % ac.g_load)
				_next("hands-off 20s")
				Controls.set_touch(Vector2(1.0, 0.0), 0.0)
		1:
			if ac.bank_deg() > 35.0 or _since() > 3.0:
				Controls.set_touch(Vector2.ZERO, 0.0)
				_check(ac.bank_deg() > 30.0 and _since() < 2.0, "rolled to 35 deg in %.1f s (bank %.0f)" % [_since(), ac.bank_deg()])
				_next("roll right")
		2:
			if _since() > 1.5 and not fbw_checked:
				fbw_checked = true
				_check(ac.bank_deg() > 30.0 and ac.bank_deg() < 75.0, "roll stops near release bank (%.0f)" % ac.bank_deg())
			if _since() > 15.0:
				_check(abs(ac.position.y - 800.0) < 250.0, "turn compensation holds altitude (%.0f)" % ac.position.y)
				_check(ac.bank_deg() > 20.0, "bank held with neutral stick (%.0f)" % ac.bank_deg())
				_check(abs(ac.beta) < deg_to_rad(3.0), "turn coordinated (beta %.1f)" % rad_to_deg(ac.beta))
				_next("15s neutral in bank")
				ac.level_out()
		3:
			if _since() > 6.0:
				_check(abs(ac.bank_deg()) < 5.0 and abs(ac.pitch_deg()) < 5.0, "level recovery (bank %.0f pitch %.0f)" % [ac.bank_deg(), ac.pitch_deg()])
				_next("after level")
				ac.start_maneuver("loop")
				loop_started = t
		4:
			if ac.maneuver() == "" or _since() > 40.0:
				_check(ac.maneuver() == "", "loop completes (%.0fs)" % _since())
				_check(abs(ac.bank_deg()) < 30.0 and abs(ac.pitch_deg()) < 30.0, "loop ends upright (bank %.0f pitch %.0f)" % [ac.bank_deg(), ac.pitch_deg()])
				_check(ac.airspeed > 50.0, "loop keeps flying speed (%.0f)" % ac.airspeed)
				_next("loop")
				ac.start_maneuver("roll")
		5:
			if ac.maneuver() == "" or _since() > 20.0:
				_check(ac.maneuver() == "", "barrel roll completes (%.0fs)" % _since())
				_check(abs(ac.bank_deg()) < 35.0, "roll ends upright (bank %.0f)" % ac.bank_deg())
				_next("roll")
				ac.level_out()
		6:
			if _since() > 5.0:
				_next("re-level")
				ac.assist = Aircraft.Assist.SIM
		7:
			if _since() > 20.0:
				_check(ac.airspeed > 60.0 and abs(ac.pitch_deg()) < 60.0, "sim hands-off stays sane (pitch %.0f spd %.0f)" % [ac.pitch_deg(), ac.airspeed])
				_next("sim 20s")
				ac.assist = Aircraft.Assist.NORMAL
				ac.level_out()
		8:
			if _since() > 5.0:
				_next("re-level")
				Controls.set_touch(Vector2(0.0, -1.0), 0.0)   # full back stick
		9:
			if _since() > 6.0:
				_check(rad_to_deg(ac.alpha) < float(ac.spec.cl_max_alpha), "AoA limiter holds (alpha %.1f, limit %.0f)" % [rad_to_deg(ac.alpha), float(ac.spec.cl_max_alpha)])
				_check(ac.g_load < float(ac.spec.g_limit) + 1.5, "G limiter holds (%.1f)" % ac.g_load)
				Controls.set_touch(Vector2.ZERO, 0.0)
				_next("6s full back stick")
				ac.level_out()
				ac.throttle_cmd = 1.0
		10:
			if _since() > 30.0:
				_check(abs(ac.bank_deg()) < 5.0 and abs(ac.pitch_deg()) < 6.0, "level at full throttle (bank %.0f pitch %.0f)" % [ac.bank_deg(), ac.pitch_deg()])
				print("max speed %.0f m/s, max G %.1f" % [ac.airspeed, ac.max_g])
				_next("full throttle 30s")
				print("RESULT ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
				get_tree().quit(0 if fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: fails += 1


func _report(label: String) -> void:
	var tm := ac.telemetry()
	print("[%5.1fs] %s: spd %.0f alt %.0f hdg %.0f pitch %.1f bank %.1f alpha %.1f g %.2f thr %.2f surf %s" % [t, label, tm.airspeed, tm.altitude, tm.heading, tm.pitch, tm.bank, tm.alpha, tm.g, tm.throttle, ac.surfaces.snapped(Vector3(0.01, 0.01, 0.01))])
