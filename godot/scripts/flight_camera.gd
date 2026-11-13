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
var base_fov := 62.0
var _shake := 0.0


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


func _unhandled_input(event: InputEvent) -> void:
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
	if not _dragging:
		_orbit_release -= delta
		if _orbit_release < 0.0:
			orbit = orbit.lerp(Vector2.ZERO, 1.0 - exp(-delta * 3.0))
	var speed := target.airspeed
	var want_fov: float = base_fov + clamp((speed - 120.0) / 220.0, 0.0, 1.0) * 14.0
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
	var k := 1.0 - exp(-delta * 5.0)
	_smooth_basis = Basis(q_from.slerp(q_to, k))
	var want := _chase_transform()
	# Critically damped spring on position: snappy but never jittery.
	var stiffness := 40.0
	var damping := 2.0 * sqrt(stiffness)
	var disp := global_position - want.origin
	_pos_vel += (-stiffness * disp - damping * _pos_vel) * delta
	global_position += _pos_vel * delta
	# Keep the aircraft in frame no matter what the spring is doing.
	look_at(target.position + (-target.basis.z) * 25.0, want.basis.y)


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
