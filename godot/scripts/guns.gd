extends Node3D
class_name Guns
## Player guns: fast tracers with arcade aim assist, hit-tested against the
## enemy ships every frame.

const SPEED := 1000.0
const LIFE := 1.6
const RATE := 11.0
const HIT_RADIUS := 14.0
const ASSIST_DEG := 8.0

var aircraft: Aircraft
var enemies: Enemies
var fx: Fx
var sfx: Sfx
var firing := false
var shots := 0
var hits := 0
var _cooldown := 0.0
var _side := 1.0
var _mesh: Mesh
var _mat: StandardMaterial3D
var _pool: Array = []
var _bullets: Array = []     # [{node, pos, vel, t}]

const ROCKET_SPEED := 300.0
const ROCKET_LIFE := 7.0
const ROCKET_TURN := deg_to_rad(140.0)
const ROCKET_MAX := 4
var rockets := ROCKET_MAX
var _rocket_regen := 0.0
var _rocket_cd := 0.0
var _missiles: Array = []    # [{node, trail, pos, vel, t, target}]
var _rocket_mesh: Mesh
var _rocket_mat: StandardMaterial3D
var fx_ref: Fx

signal hit_ship(ship: Dictionary, killed: bool)


func _ready() -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(0.22, 0.22, 9.0)
	_mesh = bm
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(1.0, 0.85, 0.3)
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.75, 0.2)
	_mat.emission_energy_multiplier = 4.0
	var rm := CapsuleMesh.new()
	rm.radius = 0.35
	rm.height = 3.2
	rm.radial_segments = 8
	rm.rings = 2
	_rocket_mesh = rm
	_rocket_mat = StandardMaterial3D.new()
	_rocket_mat.albedo_color = Color(0.9, 0.9, 0.9)
	_rocket_mat.emission_enabled = true
	_rocket_mat.emission = Color(1.0, 0.5, 0.1)
	_rocket_mat.emission_energy_multiplier = 1.5


func reset() -> void:
	for b in _bullets:
		b.node.visible = false
		_pool.append(b.node)
	_bullets.clear()
	for m in _missiles:
		m.node.queue_free()
	_missiles.clear()
	rockets = ROCKET_MAX
	_rocket_regen = 0.0
	shots = 0
	hits = 0


func _process(delta: float) -> void:
	if aircraft == null:
		return
	_cooldown -= delta
	if firing and aircraft.alive and not aircraft.frozen and _cooldown <= 0.0:
		_cooldown = 1.0 / RATE
		_shoot()
	_rocket_cd -= delta
	if rockets < ROCKET_MAX:
		_rocket_regen += delta
		if _rocket_regen >= 9.0:
			_rocket_regen = 0.0
			rockets += 1
	_step_missiles(delta)
	var keep: Array = []
	for b in _bullets:
		b.t += delta
		b.pos += b.vel * delta
		var node: MeshInstance3D = b.node
		node.global_position = b.pos
		var done: bool = b.t > LIFE
		if not done and enemies != null:
			for s in enemies.ships:
				if b.pos.distance_to(s.pos) < HIT_RADIUS:
					hits += 1
					var killed := enemies.damage(s, 1.0)
					hit_ship.emit(s, killed)
					done = true
					break
		if done:
			node.visible = false
			_pool.append(node)
		else:
			keep.append(b)
	_bullets = keep


## Fire a homing rocket at `target` (a ship dict, may be empty = dumb-fire).
func fire_rocket(target: Dictionary) -> bool:
	if rockets <= 0 or _rocket_cd > 0.0 or aircraft == null or not aircraft.alive or aircraft.frozen:
		return false
	rockets -= 1
	_rocket_cd = 0.7
	var fwd: Vector3 = -aircraft.basis.z
	var pos: Vector3 = aircraft.position + aircraft.basis.y * -1.2 + fwd * 2.0
	var node := MeshInstance3D.new()
	node.mesh = _rocket_mesh
	node.material_override = _rocket_mat
	add_child(node)
	var trail := CPUParticles3D.new()
	trail.amount = 40
	trail.lifetime = 0.9
	trail.local_coords = false
	trail.direction = Vector3.ZERO
	trail.spread = 0.0
	trail.initial_velocity_min = 0.0
	trail.initial_velocity_max = 0.0
	trail.gravity = Vector3.ZERO
	trail.scale_amount_min = 1.2
	trail.scale_amount_max = 2.2
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	if fx_ref != null:
		qm.material = fx_ref._particle_material(false)
	trail.mesh = qm
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.8, 0.5, 0.8))
	g.set_color(1, Color(0.9, 0.9, 0.9, 0.0))
	trail.color_ramp = g
	add_child(trail)
	_missiles.append({"node": node, "trail": trail, "pos": pos, "vel": fwd * (ROCKET_SPEED * 0.5) + aircraft.velocity, "t": 0.0, "target": target})
	node.global_transform = Transform3D(Basis(), pos).looking_at(pos + fwd, aircraft.basis.y) * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
	if sfx != null:
		sfx.play("boost", -8.0, 1.6)
	return true


func _step_missiles(delta: float) -> void:
	var keep: Array = []
	for m in _missiles:
		m.t += delta
		var vel: Vector3 = m.vel
		var speed: float = min(vel.length() + 260.0 * delta, ROCKET_SPEED + aircraft.airspeed)
		var dir: Vector3 = vel.normalized()
		var tgt: Dictionary = m.target
		if not tgt.is_empty() and enemies != null and enemies.ships.has(tgt):
			var to: Vector3 = (tgt.pos + tgt.vel * 0.3 - m.pos).normalized()
			var ang := dir.angle_to(to)
			if ang > 1e-4:
				dir = dir.rotated(dir.cross(to).normalized(), min(ang, ROCKET_TURN * delta))
		else:
			m.target = {}
		m.vel = dir * speed
		m.pos += m.vel * delta
		var node: MeshInstance3D = m.node
		node.global_transform = Transform3D(Basis(), m.pos).looking_at(m.pos + dir, Vector3.UP) * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
		(m.trail as CPUParticles3D).global_position = m.pos - dir * 1.5
		var done: bool = m.t > ROCKET_LIFE
		if not done and enemies != null:
			for s in enemies.ships:
				if m.pos.distance_to(s.pos) < 22.0:
					var killed := enemies.damage(s, 3.0)
					hit_ship.emit(s, killed)
					done = true
					break
		if not done and fx_ref != null and m.t > 0.3:
			var g := enemies.tiles.ground_height(m.pos) if enemies != null and enemies.tiles != null else NAN
			if not is_nan(g) and m.pos.y < g + 3.0:
				done = true
		if done:
			if fx_ref != null:
				fx_ref.burst(m.pos, true)
			node.queue_free()
			(m.trail as CPUParticles3D).emitting = false
			var tr: CPUParticles3D = m.trail
			get_tree().create_timer(1.0).timeout.connect(tr.queue_free)
		else:
			keep.append(m)
	_missiles = keep


func _shoot() -> void:
	shots += 1
	_side = -_side
	var fwd: Vector3 = -aircraft.basis.z
	var muzzle: Vector3 = aircraft.position + aircraft.basis.x * _side * float(aircraft.spec.span) * 0.18 + fwd * 3.0
	var dir := fwd
	# Aim assist: bend toward the nearest ship if it is nearly on the nose.
	if enemies != null:
		var s := enemies.nearest(aircraft.position, 1800.0)
		if not s.is_empty():
			var dist: float = s.pos.distance_to(muzzle)
			var lead: Vector3 = s.pos + s.vel * (dist / (SPEED + aircraft.airspeed))
			var to: Vector3 = (lead - muzzle).normalized()
			if rad_to_deg(fwd.angle_to(to)) < ASSIST_DEG:
				dir = to
	var node: MeshInstance3D
	if _pool.size() > 0:
		node = _pool.pop_back()
		node.visible = true
	else:
		node = MeshInstance3D.new()
		node.mesh = _mesh
		node.material_override = _mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	node.global_transform = Transform3D(Basis(), muzzle).looking_at(muzzle + dir, aircraft.basis.y)
	_bullets.append({"node": node, "pos": muzzle, "vel": dir * SPEED + aircraft.velocity, "t": 0.0})
	if sfx != null:
		sfx.play("pew", -16.0, randf_range(0.9, 1.1))
