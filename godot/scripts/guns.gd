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


func reset() -> void:
	for b in _bullets:
		b.node.visible = false
		_pool.append(b.node)
	_bullets.clear()
	shots = 0
	hits = 0


func _process(delta: float) -> void:
	if aircraft == null:
		return
	_cooldown -= delta
	if firing and aircraft.alive and not aircraft.frozen and _cooldown <= 0.0:
		_cooldown = 1.0 / RATE
		_shoot()
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
