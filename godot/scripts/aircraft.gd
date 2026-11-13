extends Node3D
class_name Aircraft
## Six-degree-of-freedom flight model with a fly-by-wire layer.
##
## Body frame: forward = -Z, right = +X, up = +Y. Angular velocity `omega` is
## in body axes: x = pitch rate (+ nose up), y = yaw rate (+ nose LEFT),
## z = roll rate (+ roll LEFT). Control inputs follow pilot convention
## (+pitch = nose up, +roll = right, +yaw = right) and are mapped onto those
## axes with explicit signs where used.
##
## Assist modes:
##   EASY   — rate command + wings auto-level + terrain floor guard
##   NORMAL — rate command, attitude hold, auto-coordination, AoA limiter
##   SIM    — stick drives the surfaces directly; stability is all aerodynamic

enum Assist { ARCADE, NORMAL, SIM }
const ASSIST_NAMES := ["Arcade", "Pro", "Sim"]

const G := 9.80665
const RHO0 := 1.225

var spec: Dictionary = Vehicles.get_spec("typhoon")
var vehicle_id := "typhoon"
var assist := Assist.ARCADE
var boost := 0.0          # 0..1 afterburner/boost amount (arcade)
var boost_energy := 1.0   # 0..1, drains while boosting

# ---- state (local frame) ----
var velocity := Vector3.ZERO
var omega := Vector3.ZERO
var throttle := 0.7
var throttle_cmd := 0.7
var alive := true
var frozen := true
var input_enabled := true

# ---- telemetry ----
var airspeed := 0.0
var alpha := 0.0
var beta := 0.0
var g_load := 1.0
var altitude_agl := NAN
var ground_y := NAN
var stall := false
var distance_m := 0.0
var flight_time := 0.0
var surfaces := Vector3.ZERO   # elevator, aileron, rudder (-1..1)
var max_g := 1.0

# ---- fly-by-wire internals ----
var _pitch_i := 0.0
var _trim := 0.0
var _act := Vector3.ZERO
var fbw_dbg := {}
var _maneuver := ""           # "", "loop", "roll", "level"
var _maneuver_acc := 0.0
var _hold_pitch := 0.0
var _hold_bank := 0.0
var _hold_timer := 0.0
var _ground_ray_timer := 0.0

var model: Node3D
var _surface_nodes: Dictionary = {}
var _surface_rest: Dictionary = {}
var _wing_nodes: Dictionary = {}
var _wing_rest: Dictionary = {}
var _sweep := 0.0
var tiles: GoogleTiles

signal crashed
signal maneuver_done(kind: String)


func _ready() -> void:
	set_vehicle(vehicle_id)


func set_vehicle(id: String) -> void:
	vehicle_id = id
	spec = Vehicles.get_spec(id)
	if model != null:
		model.queue_free()
		model = null
	_surface_nodes.clear()
	_surface_rest.clear()
	var packed: PackedScene = load(spec.model)
	if packed == null:
		push_warning("Missing model " + str(spec.model))
		return
	var holder := Node3D.new()
	holder.name = "Model"
	# Models are authored with +Z forward; Godot flies along -Z.
	holder.rotation.y = PI + deg_to_rad(float(spec.get("model_yaw", 0.0)))
	holder.scale = Vector3.ONE * float(spec.model_scale)
	var inst := packed.instantiate()
	holder.add_child(inst)
	add_child(holder)
	model = holder
	for n: String in spec.surfaces.keys():
		var found := inst.find_child(n, true, false)
		if found is Node3D:
			_surface_nodes[n] = found
			_surface_rest[n] = (found as Node3D).transform
	_wing_nodes.clear()
	if spec.has("wing_sweep"):
		for side in ["left", "right"]:
			var w := inst.find_child(spec.wing_sweep[side], true, false)
			if w is Node3D:
				_wing_nodes[side] = w
				_wing_rest[side] = (w as Node3D).transform
	_apply_paint(inst)


## Re-skin the imported materials: the source packs ship flat colours named
## gray / dark_gray / black / glass. Give them a metallic paint look, the
## canopy a dark glossy tint, and let shadows fall on the model.
func _apply_paint(root: Node) -> void:
	var paint: Dictionary = spec.get("paint", {})
	var stack: Array = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mi.mesh == null:
			continue
		for si in range(mi.mesh.get_surface_count()):
			var src := mi.mesh.surface_get_material(si)
			var name := (src.resource_name if src else "").to_lower()
			var m := StandardMaterial3D.new()
			var base: Color = (src as BaseMaterial3D).albedo_color if src is BaseMaterial3D else Color(0.6, 0.6, 0.6)
			if src is BaseMaterial3D and (src as BaseMaterial3D).albedo_texture != null:
				m.albedo_texture = (src as BaseMaterial3D).albedo_texture
			m.metallic = 0.55
			m.roughness = 0.4
			m.metallic_specular = 0.6
			if "glass" in name or "canopy" in name:
				m.albedo_color = Color(0.08, 0.12, 0.16)
				m.metallic = 0.9
				m.roughness = 0.08
			elif "black" in name:
				m.albedo_color = Color(0.06, 0.06, 0.07)
				m.metallic = 0.3
				m.roughness = 0.6
			elif "dark" in name:
				m.albedo_color = paint.get("dark", base.darkened(0.3))
			elif "red" in name or "accent" in name:
				m.albedo_color = paint.get("accent", base)
			elif "gray" in name or "grey" in name or "tan" in name or "lt_" in name or "body" in name:
				m.albedo_color = paint.get("body", base)
			else:
				m.albedo_color = base
				m.metallic = 0.35
				m.roughness = 0.5
			mi.set_surface_override_material(si, m)


func set_model_visible(v: bool) -> void:
	if model:
		model.visible = v


## Place the aircraft at a geodetic position, flying level on `heading_deg`.
func spawn(lat: float, lon: float, alt_m: float, heading_deg: float, speed: float = -1.0) -> void:
	position = Geo.geodetic_to_local(lat, lon, alt_m)
	var yaw := deg_to_rad(-heading_deg)   # heading 0 = north = -Z; positive = clockwise
	basis = Basis(Vector3.UP, yaw)
	var spd: float = speed if speed > 0.0 else float(spec.spawn_speed)
	velocity = -basis.z * spd
	omega = Vector3.ZERO
	throttle = 0.7
	throttle_cmd = 0.7
	alive = true
	_maneuver = ""
	_pitch_i = 0.0
	_trim = 0.0
	_act = Vector3.ZERO
	_hold_pitch = 0.0
	_hold_bank = 0.0
	distance_m = 0.0
	flight_time = 0.0
	max_g = 1.0
	boost = 0.0
	boost_energy = 1.0
	set_model_visible(true)


func geodetic() -> Array:
	return Geo.local_to_geodetic(position)


func heading_deg() -> float:
	var f := -basis.z
	var h := rad_to_deg(atan2(f.x, -f.z))
	return fposmod(h, 360.0)


func pitch_deg() -> float:
	return rad_to_deg(asin(clamp(-basis.z.y, -1.0, 1.0)))


func bank_deg() -> float:
	# Roll angle relative to the horizon (+ = right wing down).
	var right := basis.x
	var up := basis.y
	return rad_to_deg(atan2(-right.y, up.y))


func cycle_assist() -> void:
	assist = ((assist + 1) % 3) as Assist


func start_maneuver(kind: String) -> void:
	if not alive or frozen:
		return
	if assist == Assist.SIM:
		assist = Assist.NORMAL
	_maneuver = kind
	_maneuver_acc = 0.0


## Called by Main after the origin moves; `rot` maps old-local to new-local.
func rebase(new_pos: Vector3, rot: Basis) -> void:
	position = new_pos
	basis = (rot * basis).orthonormalized()
	velocity = rot * velocity


# ------------------------------------------------------------------ physics

func _physics_process(delta: float) -> void:
	if frozen or not alive:
		return
	flight_time += delta
	var steps := 2
	var h := delta / steps
	for _i in range(steps):
		_step(h)
	_animate_surfaces()
	_check_ground()


func _step(dt: float) -> void:
	var m: float = spec.mass
	var S: float = spec.wing_area
	var c: float = spec.chord
	var b: float = spec.span
	var I: Vector3 = spec.inertia

	# Atmosphere.
	var alt: float = position.y + Geo.origin_h
	var rho := RHO0 * exp(-max(alt, 0.0) / 8500.0)

	# Relative wind in body axes.
	var v_b := basis.inverse() * velocity
	var u := -v_b.z           # forward
	var v := v_b.x            # right
	var w := v_b.y            # up
	airspeed = velocity.length()
	var V: float = max(airspeed, 1.0)
	alpha = atan2(-w, max(u, 0.5))
	beta = atan2(v, max(u, 0.5))
	var q_dyn := 0.5 * rho * V * V

	# Controls (pilot convention) -> surface deflections.
	var cmd := _fly_by_wire(dt, V, q_dyn)
	var de := cmd.x
	var da := cmd.y
	var dr := cmd.z
	surfaces = Vector3(de, da, dr)

	# Lift / drag coefficients with a soft stall.
	var a_s := deg_to_rad(float(spec.cl_max_alpha) + (8.0 if assist == Assist.ARCADE else 0.0))
	var cl_lin: float = spec.cl0 + spec.cla * alpha
	var cl: float
	var over: float = abs(alpha) - a_s
	if over <= 0.0:
		cl = cl_lin
		stall = over > -deg_to_rad(2.0) and airspeed > 20.0
	else:
		var fade: float = clamp(1.0 - over / deg_to_rad(14.0), 0.0, 1.0)
		var cl_edge: float = spec.cl0 + spec.cla * a_s * sign(alpha)
		var cl_flat := 1.1 * sin(2.0 * alpha) * 0.5
		cl = cl_edge * fade + cl_flat * (1.0 - fade)
		stall = true
	var cd: float = spec.cd0 + spec.k_induced * cl * cl + (spec.brake_drag if Controls.brake else 0.0)
	if over > 0.0:
		cd += 0.9 * over
	cd += 0.6 * beta * beta

	# Forces in the local frame.
	var vhat := velocity / V
	var body_up := basis.y
	var lift_dir := body_up - vhat * body_up.dot(vhat)
	if lift_dir.length_squared() < 1e-6:
		lift_dir = body_up
	lift_dir = lift_dir.normalized()
	var lift := q_dyn * S * cl
	var drag := q_dyn * S * cd
	var side := q_dyn * S * float(spec.cyb) * beta
	var thrust_max: float = spec.thrust * (0.35 + 0.65 * rho / RHO0)
	var thrust := throttle * thrust_max * (1.0 + 0.6 * boost)
	var F := -basis.z * thrust + lift_dir * lift - vhat * drag + basis.x * side
	var accel := F / m + Vector3(0, -G, 0)
	g_load = (F / m).dot(basis.y) / G
	max_g = max(max_g, abs(g_load))

	# Moments in body axes.
	var qc := c / (2.0 * V)
	var qb := b / (2.0 * V)
	var pitch_rate := omega.x
	var yaw_rate := omega.y     # + nose left
	var roll_rate := omega.z    # + roll left
	var cm: float = spec.cm0 + spec.cma * alpha + spec.cmq * pitch_rate * qc + spec.cmde * de
	# Yaw: weathervane turns the nose toward the wind (+beta -> nose right -> -Y).
	var cn: float = -spec.cnb * beta + spec.cnr * yaw_rate * qb - spec.cndr * dr - spec.cnda * da
	# Roll: +aileron = roll right = -Z; dihedral rolls away from sideslip.
	var cl_roll: float = spec.clb * beta + spec.clp * roll_rate * qb - spec.clda * da
	var M := Vector3(q_dyn * S * c * cm, q_dyn * S * b * cn, q_dyn * S * b * cl_roll)
	if float(spec.rcs) > 0.0:
		# Vectored thrust: authority that does not depend on airspeed.
		var rcs: float = spec.rcs * (0.3 + 0.7 * throttle)
		M += Vector3(de * rcs, -dr * rcs * 0.5, -da * rcs)
		# ... and strong damping so it stays controllable.
		M -= Vector3(omega.x * I.x, omega.y * I.y, omega.z * I.z) * 2.5
	var Iw := Vector3(I.x * omega.x, I.y * omega.y, I.z * omega.z)
	var ang_acc := Vector3((M.x - (omega.cross(Iw)).x) / I.x, (M.y - (omega.cross(Iw)).y) / I.y, (M.z - (omega.cross(Iw)).z) / I.z)

	# Integrate (semi-implicit Euler).
	omega += ang_acc * dt
	omega = omega.limit_length(8.0)
	velocity += accel * dt
	var step := velocity * dt
	position += step
	distance_m += step.length()
	var w_len := omega.length()
	if w_len > 1e-6:
		basis = (basis * Basis(omega / w_len, w_len * dt)).orthonormalized()

	# Throttle spool.
	throttle = move_toward(throttle, throttle_cmd, dt / float(spec.spool))


## Returns (elevator, aileron, rudder) in -1..1, after actuator rate limits.
func _fly_by_wire(dt: float, V: float, q_dyn: float) -> Vector3:
	var cmd := _control_law(dt, V, q_dyn)
	# Actuators: full travel in ~0.12 s so the surfaces move, never snap.
	var rate := dt * 8.0
	_act.x = move_toward(_act.x, cmd.x, rate)
	_act.y = move_toward(_act.y, cmd.y, rate)
	_act.z = move_toward(_act.z, cmd.z, rate)
	return _act


func _control_law(dt: float, V: float, q_dyn: float) -> Vector3:
	var pitch_in := Controls.pitch if input_enabled else 0.0
	var roll_in := Controls.roll if input_enabled else 0.0
	var yaw_in := Controls.yaw if input_enabled else 0.0
	if input_enabled:
		if assist == Assist.ARCADE:
			# Arcade: engine runs itself. Hold boost for afterburner, hold
			# brake to slow down; the plane otherwise cruises.
			var want_boost: bool = Controls.throttle_delta > 0.5 and boost_energy > 0.02
			boost = move_toward(boost, 1.0 if want_boost else 0.0, dt * 3.0)
			boost_energy = clamp(boost_energy + (-0.22 if want_boost else 0.12) * dt, 0.0, 1.0)
			var cruise: float = 0.45 if not Controls.brake else 0.12
			throttle_cmd = clamp(cruise + boost * 0.38, 0.0, 1.0)
		else:
			boost = move_toward(boost, 0.0, dt * 3.0)
			boost_energy = min(boost_energy + 0.12 * dt, 1.0)
			throttle_cmd = clamp(throttle_cmd + Controls.throttle_delta * dt * 0.5, 0.0, 1.0)

	var S: float = spec.wing_area
	var I: Vector3 = spec.inertia
	# Control power (rad/s^2 per unit deflection) — the basis of every gain.
	var m_de: float = max((q_dyn * S * spec.chord * spec.cmde + spec.rcs * (0.3 + 0.7 * throttle)) / I.x, 0.05)
	var l_da: float = max((q_dyn * S * spec.span * spec.clda + spec.rcs * (0.3 + 0.7 * throttle)) / I.z, 0.05)

	if assist == Assist.SIM and _maneuver == "":
		# Direct law with an auto-trim wheel: when the stick is centred the
		# trim slowly removes any residual pitch rate (as a pilot would).
		if abs(pitch_in) < 0.05:
			_trim = clamp(_trim - omega.x * dt * 0.6, -0.5, 0.5)
		_pitch_i = 0.0
		return Vector3(clamp(pitch_in * 0.7 + _trim, -1.0, 1.0), roll_in, yaw_in)

	var rates: Vector3 = spec.max_rates
	var bank := deg_to_rad(bank_deg())
	var pitch := deg_to_rad(pitch_deg())
	var target_q := pitch_in * deg_to_rad(rates.x)
	var target_p := roll_in * deg_to_rad(rates.z)   # + = roll right

	# Scripted maneuvers override the stick.
	match _maneuver:
		"loop":
			# Pitch as hard as the stunt G limit allows; keep roll rate at zero
			# (bank angle is meaningless while inverted, so never chase it).
			# Decelerate over the last part so the exit is level.
			var remaining_l: float = TAU - _maneuver_acc
			target_q = min(min(deg_to_rad(rates.x) * 1.2, float(spec.get("stunt_g", 7.0)) * G / V), remaining_l / 0.4)
			target_p = 0.0
			throttle_cmd = 1.0
			_maneuver_acc += omega.x * dt
			if remaining_l < 0.02:
				_end_maneuver()
		"roll":
			var remaining_r: float = TAU - _maneuver_acc
			target_p = min(deg_to_rad(rates.z) * 0.9, remaining_r / 0.25)
			target_q = deg_to_rad(10.0) * clamp(remaining_r / 1.0, 0.0, 1.0)
			_maneuver_acc += -omega.z * dt
			if remaining_r < 0.02:
				_end_maneuver()
		"level":
			target_p = -bank * 3.0
			target_q = -pitch * 2.5
			if abs(bank) < deg_to_rad(2.0) and abs(pitch) < deg_to_rad(2.0):
				_end_maneuver()

	# Arcade: wings level themselves when the stick is centred, and the nose
	# drifts back to the horizon — point and go.
	if assist == Assist.ARCADE and _maneuver == "":
		if abs(roll_in) < 0.05:
			target_p += -bank * 1.6
		if abs(pitch_in) < 0.05 and abs(bank) < deg_to_rad(60.0):
			target_q += -pitch * 0.9
	# Arcade: terrain floor guard.
	if assist == Assist.ARCADE and _maneuver == "" and not is_nan(altitude_agl):
		var sink := -velocity.y
		var ttc: float = altitude_agl / max(sink, 0.1)
		if sink > 0.0 and ttc < 5.0:
			target_q = max(target_q, deg_to_rad(rates.x) * clamp((5.0 - ttc) / 3.0, 0.0, 1.0))
			if ttc < 2.0:
				target_p += -bank * 2.0   # and get the wings level to pull

	# Turn compensation: neutral stick holds altitude through a bank. It
	# fades out past 75 deg — beyond vertical, pitching "up" only drives the
	# nose into the ground, and inverted flight is the pilot's business.
	if _maneuver == "":
		var ab: float = abs(bank)
		var bank_c: float = min(ab, deg_to_rad(75.0))
		var fade: float = clamp((deg_to_rad(90.0) - ab) / deg_to_rad(15.0), 0.0, 1.0)
		target_q += (G / V) * tan(bank_c) * sin(bank_c) * fade

	# G limiter (approximate: g ~ V*q/G). Stunts get extra headroom.
	var g_lim: float = spec.get("stunt_g", 7.0) if (_maneuver != "" or assist == Assist.ARCADE) else spec.get("g_limit", 5.0)
	target_q = clamp(target_q, -(0.5 * g_lim + 1.0) * G / V, (g_lim + 1.0) * G / V)

	# AoA limiter: never command past the stall.
	var a_lim := deg_to_rad(float(spec.cl_max_alpha) - 1.5 + (8.0 if assist == Assist.ARCADE else 0.0))
	var margin := a_lim - alpha
	if margin < deg_to_rad(5.0):
		target_q = min(target_q, margin * 5.0)
	if alpha < -a_lim * 0.7:
		target_q = max(target_q, 0.0)

	# Pitch: feedforward cancels static stability and damping at the target
	# rate, then an inverted-dynamics P loop (tau ~0.15 s) plus an integrator
	# removes what the model does not know about.
	var qc: float = spec.chord / (2.0 * V)
	var de_ff: float = -(spec.cm0 + spec.cma * alpha + spec.cmq * target_q * qc) / spec.cmde if spec.cmde > 0.0 else 0.0
	var q_err := target_q - omega.x
	_pitch_i = clamp(_pitch_i + q_err * dt / (m_de * 0.5), -0.5, 0.5)
	if _maneuver != "":
		_pitch_i = move_toward(_pitch_i, 0.0, dt * 0.5)
	var de: float = clamp(de_ff + q_err / (m_de * 0.15) + _pitch_i, -1.0, 1.0)
	fbw_dbg = {"tq": target_q, "q": omega.x, "de_ff": de_ff, "p": q_err / (m_de * 0.15), "i": _pitch_i, "de": de, "m_de": m_de}

	# Roll: inverted dynamics on roll rate.
	var qb: float = spec.span / (2.0 * V)
	var da_ff: float = (spec.clb * beta + spec.clp * (-target_p) * qb) / spec.clda if spec.clda > 0.0 else 0.0
	var p_err := target_p - (-omega.z)
	var da: float = clamp(da_ff + p_err / (l_da * 0.08), -1.0, 1.0)

	# Auto-coordination: rudder cancels sideslip, plus pilot rudder.
	var dr: float = clamp(yaw_in + beta * 3.0, -1.0, 1.0)
	return Vector3(de, da, dr)


func _end_maneuver() -> void:
	var k := _maneuver
	_maneuver = ""
	_maneuver_acc = 0.0
	maneuver_done.emit(k)


func maneuver() -> String:
	return _maneuver


func level_out() -> void:
	start_maneuver("level")


# ------------------------------------------------------------- environment

var ground_check_err := ""


func _check_ground() -> void:
	if tiles == null:
		ground_check_err = "no tiles"
		return
	ground_check_err = "ran"
	# Altitude above ground (ray from the aircraft straight down).
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(position + Vector3(0, 2, 0), position + Vector3(0, -6000, 0), 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		altitude_agl = NAN
		ground_y = NAN
	else:
		ground_y = hit.position.y
		altitude_agl = position.y - ground_y
	# Collision: anything inside the hull sphere, or a sweep along the velocity.
	var shape := SphereShape3D.new()
	shape.radius = float(spec.radius) * 0.8
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = shape
	sq.transform = Transform3D(Basis(), position)
	sq.collision_mask = 1
	var hits := space.intersect_shape(sq, 1)
	if hits.size() > 0:
		_crash()
		return
	var sweep := PhysicsRayQueryParameters3D.create(position, position + velocity * (1.0 / 60.0) * 2.0, 1)
	if not space.intersect_ray(sweep).is_empty():
		_crash()


func _crash() -> void:
	if not alive:
		return
	alive = false
	crashed.emit()


func _animate_surfaces() -> void:
	if _wing_nodes.size() == 2:
		# Swing wings: spread at low speed, swept back when fast.
		var want: float = clamp((airspeed - 120.0) / 160.0, 0.0, 1.0)
		_sweep = move_toward(_sweep, want, 1.0 / 60.0 * 0.25)
		var ang := deg_to_rad(float(spec.wing_sweep.max_deg)) * _sweep
		(_wing_nodes["left"] as Node3D).transform = _wing_rest["left"] * Transform3D(Basis(Vector3.UP, -ang), Vector3.ZERO)
		(_wing_nodes["right"] as Node3D).transform = _wing_rest["right"] * Transform3D(Basis(Vector3.UP, ang), Vector3.ZERO)
	for n: String in _surface_nodes.keys():
		var cfg: Array = spec.surfaces[n]
		var kind: int = cfg[0]
		var max_deg: float = cfg[1]
		var sgn: float = cfg[2]
		var amount := 0.0
		var axis := Vector3.RIGHT
		match kind:
			0: amount = surfaces.x            # elevator
			1: amount = surfaces.y            # aileron
			2:
				amount = surfaces.z            # rudder
				axis = Vector3.UP
			3: amount = surfaces.x - surfaces.y * 0.6   # elevon L
			4: amount = surfaces.x + surfaces.y * 0.6   # elevon R
		var node: Node3D = _surface_nodes[n]
		var rest: Transform3D = _surface_rest[n]
		node.transform = rest * Transform3D(Basis(axis, deg_to_rad(clamp(amount, -1.0, 1.0) * max_deg * sgn)), Vector3.ZERO)


func debug_line() -> String:
	var v_b := basis.inverse() * velocity
	return "vel %s v_b %s omega %s act %s trim %.2f i %.2f" % [velocity.snapped(Vector3(0.1, 0.1, 0.1)), v_b.snapped(Vector3(0.1, 0.1, 0.1)), omega.snapped(Vector3(0.001, 0.001, 0.001)), _act.snapped(Vector3(0.01, 0.01, 0.01)), _trim, _pitch_i]


func telemetry() -> Dictionary:
	return {
		"airspeed": airspeed,
		"altitude": position.y + Geo.origin_h,
		"agl": altitude_agl,
		"heading": heading_deg(),
		"pitch": pitch_deg(),
		"bank": bank_deg(),
		"throttle": throttle,
		"throttle_cmd": throttle_cmd,
		"g": g_load,
		"alpha": rad_to_deg(alpha),
		"stall": stall,
		"assist": ASSIST_NAMES[assist],
		"distance": distance_m,
		"time": flight_time,
		"vehicle": spec.name,
		"maneuver": _maneuver,
		"vs": velocity.y,
		"boost": boost,
		"boost_energy": boost_energy,
	}
