extends Camera3D
class_name FlightCamera
## Chase / cockpit / fly-by cameras with mouse orbit and speed-driven FOV.

enum Mode { CHASE, COCKPIT, FLYBY }
const MODE_NAMES := ["Chase", "Cockpit", "Fly-by"]

var target: Aircraft
var mode := Mode.CHASE
var orbit := Vector2.ZERO          # yaw, pitch offsets (rad) from mouse drag
var _dragging := false
var _orbit_release := 0.0
var _smooth_basis := Basis()
var _pos_vel := Vector3.ZERO
var _flyby_pos := Vector3.ZERO
var _flyby_timer := 0.0
var base_fov := 60.0
var _shake := 0.0
var look_target: Vector3 = Vector3.INF   # locked enemy, or INF for none
var _lean := Vector2.ZERO


func _ready() -> void:
	near = 1.5
	far = 120000.0
	fov = base_fov
	current = true


func cycle_mode() -> void:
	mode = ((mode + 1) % 3) as Mode
	if target:
		target.set_model_visible(mode != Mode.COCKPIT)
	if mode == Mode.FLYBY:
		_place_flyby()


func set_mode(m: Mode) -> void:
	mode = m
	if target:
		target.set_model_visible(mode != Mode.COCKPIT)
	if mode == Mode.FLYBY:
		_place_flyby()


func snap() -> void:
	# Jump to the ideal spot (after spawn / rebase) instead of easing there.
	if target == null:
		return
	_smooth_basis = target.basis
	var want := _chase_transform()
	global_transform = want
	_pos_vel = Vector3.ZERO


func kick(amount: float) -> void:
	_shake = max(_shake, amount)


func _unhandled_input_disabled(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
			if not mb.pressed:
				_orbit_release = 2.0
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		orbit.x -= mm.relative.x * 0.005
		orbit.y = clamp(orbit.y - mm.relative.y * 0.005, -1.2, 1.2)
		_orbit_release = 2.0


func _process(delta: float) -> void:
	if target == null:
		return
	pass
	var speed := target.airspeed
	var want_fov: float = base_fov + clamp((speed - 140.0) / 220.0, 0.0, 1.0) * 8.0 + 10.0 * target.boost
	if mode == Mode.COCKPIT:
		want_fov += 8.0
	fov = lerp(fov, want_fov, 1.0 - exp(-delta * 2.0))

	match mode:
		Mode.CHASE:
			_update_chase(delta)
		Mode.COCKPIT:
			_update_cockpit()
		Mode.FLYBY:
			_update_flyby(delta)
	if _shake > 0.0:
		_shake = max(_shake - delta * 2.0, 0.0)
		global_position += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * _shake * 0.6


func _chase_transform() -> Transform3D:
	var spec := target.spec
	var offset: Vector3 = spec.chase
	# Follow heading and pitch fully, roll only partly: the horizon stays
	# readable while the aircraft banks under you.
	var b := _smooth_basis
	var fwd := -b.z
	var up_mix := b.y.lerp(Vector3.UP, 0.55)
	var right := fwd.cross(up_mix).normalized()
	var up := right.cross(fwd).normalized()
	var cam_basis := Basis(right, up, -fwd)
	var rot := Basis(up, orbit.x) * Basis(right, orbit.y)
	cam_basis = rot * cam_basis
	var pos: Vector3 = target.position + cam_basis * Vector3(offset.x, offset.y, offset.z)
	var look_at_pos: Vector3 = target.position + fwd * 30.0 + up * 2.0
	var t := Transform3D(cam_basis, pos)
	return t.looking_at(look_at_pos, up)


func _update_chase(delta: float) -> void:
	# Ease the reference basis so quick rolls don't yank the camera.
	var q_from := _smooth_basis.get_rotation_quaternion()
	var q_to := target.basis.get_rotation_quaternion()
	var k := 1.0 - exp(-delta * 7.0)
	_smooth_basis = Basis(q_from.slerp(q_to, k))
	# Lean the view toward the locked target (never more than ~22 deg).
	var want_lean := Vector2.ZERO
	if look_target != Vector3.INF:
		var local: Vector3 = target.basis.inverse() * (look_target - target.position)
		if local.z < 0.0:
			want_lean = Vector2(clamp(atan2(local.x, -local.z), -0.4, 0.4), clamp(atan2(local.y, -local.z), -0.3, 0.3))
	_lean = _lean.lerp(want_lean, 1.0 - exp(-delta * 2.5))
	orbit = Vector2(-_lean.x, _lean.y)
	var want := _chase_transform()
	# Critically damped spring on position: snappy but never jittery.
	var stiffness := 55.0
	var damping := 2.0 * sqrt(stiffness)
	var disp := global_position - want.origin
	_pos_vel += (-stiffness * disp - damping * _pos_vel) * delta
	global_position += _pos_vel * delta
	# Keep the aircraft in frame no matter what the spring is doing.
	var ahead: Vector3 = target.position + (-target.basis.z) * 25.0
	if look_target != Vector3.INF:
		ahead = ahead.lerp(look_target, 0.08)
	look_at(ahead, want.basis.y)


func _update_cockpit() -> void:
	var spec := target.spec
	var off: Vector3 = spec.cockpit
	var b := target.basis
	var rot := b * Basis(Vector3.UP, orbit.x) * Basis(Vector3.RIGHT, orbit.y)
	global_transform = Transform3D(rot, target.position + b * off)


func _place_flyby() -> void:
	var ahead: Vector3 = target.position + target.velocity * 4.0
	var side := (-target.basis.z).cross(Vector3.UP).normalized()
	_flyby_pos = ahead + side * (120.0 * (1.0 if randf() > 0.5 else -1.0)) + Vector3(0, randf_range(-30.0, 60.0), 0)
	_flyby_timer = 9.0


func _update_flyby(delta: float) -> void:
	_flyby_timer -= delta
	if _flyby_timer <= 0.0 or global_position.distance_to(target.position) > 1500.0:
		_place_flyby()
	global_position = _flyby_pos
	look_at(target.position, Vector3.UP)
