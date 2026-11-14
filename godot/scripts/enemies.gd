extends Node3D
class_name Enemies
## Enemy spaceships: spawn in waves around the player, cruise between
## waypoints, weave when chased, and fire slow bolts the player can dodge.
## Kinematic (no physics bodies): cheap enough for phones.

const MODEL := "res://assets/nova.glb"
const SHIP_RADIUS := 9.0
const BOLT_SPEED := 330.0
const BOLT_LIFE := 3.2
const BOLT_RADIUS := 9.0
const TINTS := [
	[Color(0.35, 0.08, 0.5), Color(0.9, 0.3, 1.0)],
	[Color(0.08, 0.3, 0.3), Color(0.2, 1.0, 0.8)],
	[Color(0.45, 0.1, 0.1), Color(1.0, 0.35, 0.2)],
]

var aircraft: Aircraft
var tiles: GoogleTiles
var fx: Fx
var ships: Array = []        # [{node, pos, vel, speed, hp, wp, t_fire, weave, tint}]
var bolts: Array = []        # [{node, pos, vel, t}]
var wave := 0
var kills := 0
var arena_centre := Vector3.ZERO
var arena_radius := 2500.0
var active := false
var _packed: PackedScene
var _bolt_mesh: Mesh
var _bolt_mat: StandardMaterial3D
var _bolt_pool: Array = []
var _respawn_timer := 0.0

signal ship_killed(pos: Vector3)
signal player_hit(damage: float)
signal wave_cleared(n: int)


func _ready() -> void:
	_packed = load(MODEL)
	var bm := CapsuleMesh.new()
	bm.radius = 0.6
	bm.height = 7.0
	bm.radial_segments = 6
	bm.rings = 2
	_bolt_mesh = bm
	_bolt_mat = StandardMaterial3D.new()
	_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt_mat.albedo_color = Color(1.0, 0.3, 0.9)
	_bolt_mat.emission_enabled = true
	_bolt_mat.emission = Color(1.0, 0.3, 0.9)
	_bolt_mat.emission_energy_multiplier = 4.0


func start() -> void:
	clear()
	wave = 0
	kills = 0
	active = true
	_next_wave()


func clear() -> void:
	for s in ships:
		s.node.queue_free()
	ships.clear()
	for b in bolts:
		b.node.visible = false
		_bolt_pool.append(b.node)
	bolts.clear()
	active = false


func _next_wave() -> void:
	wave += 1
	var n: int = min(2 + wave, 6)
	for i in range(n):
		_spawn_ship(i, n)


func _spawn_ship(i: int, n: int) -> void:
	var inst := _packed.instantiate()
	var node := Node3D.new()
	var holder := Node3D.new()
	holder.rotation.y = PI - PI * 0.5   # nova model nose is along +X in glTF
	holder.add_child(inst)
	node.add_child(holder)
	add_child(node)
	var tint: Array = TINTS[(i + wave) % TINTS.size()]
	_paint(inst, tint[0], tint[1])
	# Ahead of the player, fanned out, a few hundred metres up or down.
	var fwd: Vector3 = -aircraft.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	var ang: float = (float(i) / max(n - 1, 1) - 0.5) * 1.6
	var dir: Vector3 = (fwd * cos(ang) + side * sin(ang)).normalized()
	var pos: Vector3 = aircraft.position + dir * randf_range(900.0, 1600.0) + Vector3(0, randf_range(-150.0, 250.0), 0)
	pos.y = _safe_alt(pos)
	var speed: float = randf_range(140.0, 165.0) + float(min(wave, 6)) * 4.0
	var ship := {"node": node, "pos": pos, "vel": fwd * speed, "speed": speed, "hp": 3.0, "wp": pos, "t_fire": randf_range(1.0, 3.0), "weave": randf() * TAU, "tint": tint[1], "turn": 0.0, "hunt": 0.0, "t_mode": randf_range(2.0, 5.0)}
	ship.wp = _new_waypoint(ship)
	node.global_position = pos
	ships.append(ship)


## Test helper: a stationary ship straight ahead of the player.
func spawn_dummy(dist: float = 450.0) -> void:
	_spawn_ship(0, 1)
	var s: Dictionary = ships[-1]
	s.pos = aircraft.position + (-aircraft.basis.z) * dist
	s.speed = 0.0
	s.vel = Vector3.ZERO
	s.t_fire = 1e9
	s.wp = s.pos
	(s.node as Node3D).global_position = s.pos


func _paint(root: Node, base: Color, glow: Color) -> void:
	var stack: Array = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var m := StandardMaterial3D.new()
			m.albedo_color = base
			m.metallic = 0.6
			m.roughness = 0.35
			m.emission_enabled = true
			m.emission = glow
			m.emission_energy_multiplier = 0.9
			for si in range(mi.mesh.get_surface_count() if mi.mesh else 0):
				mi.set_surface_override_material(si, m)


func _safe_alt(p: Vector3) -> float:
	var g := NAN
	if tiles != null:
		g = tiles.ground_height(p)
	var floor_y: float = (g + 160.0) if not is_nan(g) else 150.0
	return max(p.y, floor_y)


func _new_waypoint(s: Dictionary) -> Vector3:
	# Around the player, but always inside the arena so the fight stays over
	# the loaded city.
	var centre: Vector3 = aircraft.position
	var a := randf() * TAU
	var r := randf_range(500.0, 1500.0)
	var wp := centre + Vector3(cos(a) * r, randf_range(-200.0, 300.0), sin(a) * r)
	var from_c: Vector3 = wp - arena_centre
	from_c.y = 0.0
	if from_c.length() > arena_radius * 0.8:
		wp = arena_centre + from_c.normalized() * arena_radius * 0.6 + Vector3(0, wp.y - arena_centre.y, 0)
	wp.y = _safe_alt(wp)
	return wp


func _process(delta: float) -> void:
	if not active or aircraft == null:
		return
	var pp: Vector3 = aircraft.position
	for s in ships:
		_step_ship(s, delta, pp)
	_step_bolts(delta, pp)
	if ships.is_empty():
		_respawn_timer += delta
		if _respawn_timer > 2.5:
			_respawn_timer = 0.0
			wave_cleared.emit(wave)
			_next_wave()


func _step_ship(s: Dictionary, delta: float, pp: Vector3) -> void:
	var pos: Vector3 = s.pos
	var to_wp: Vector3 = s.wp - pos
	if to_wp.length() < 180.0:
		s.wp = _new_waypoint(s)
		to_wp = s.wp - pos
	var want: Vector3 = to_wp.normalized()
	var rel: Vector3 = pp - pos
	var chased: bool = rel.length() < 900.0 and rel.normalized().dot(s.vel.normalized()) < -0.3
	# Hunt / cruise mode switching: hunters turn in on the player and shoot.
	s.t_mode -= delta
	if s.t_mode <= 0.0:
		s.t_mode = randf_range(4.0, 7.0)
		s.hunt = 1.0 if (randf() < 0.55 + min(wave, 5) * 0.06) else 0.0
	if s.hunt > 0.0 and rel.length() > 250.0:
		# Aim at where the player will be in a second or so.
		var lead: Vector3 = pp + aircraft.velocity * 1.2
		want = (lead - pos).normalized()
	elif s.hunt > 0.0:
		# Too close: swing wide to set up another pass.
		want = (want + s.vel.normalized() * 0.5).normalized()
	s.weave += delta * (2.2 if chased else 0.8)
	var side: Vector3 = s.vel.normalized().cross(Vector3.UP)
	var weave_amt: float = (0.9 if chased else 0.25) * (0.3 if s.hunt > 0.0 else 1.0)
	want += side * sin(s.weave) * weave_amt + Vector3(0, cos(s.weave * 0.7) * 0.2, 0)
	want = want.normalized()
	# Turn toward the wanted direction at a limited rate.
	var cur: Vector3 = s.vel.normalized()
	var max_turn := deg_to_rad(55.0 if (chased or s.hunt > 0.0) else 35.0) * delta
	var angle := cur.angle_to(want)
	var ndir: Vector3 = cur
	if s.speed <= 0.0:
		return
	if angle > 1e-4:
		var axis := cur.cross(want)
		if axis.length() < 1e-4:
			axis = Vector3.UP
		ndir = cur.rotated(axis.normalized(), min(angle, max_turn))
	s.vel = ndir * s.speed
	pos += s.vel * delta
	var floor_y := _safe_alt(pos)
	if pos.y < floor_y:
		pos.y = floor_y
		s.vel.y = abs(s.vel.y) * 0.5
	s.pos = pos
	# Pose: face velocity, bank into turns.
	var node: Node3D = s.node
	var fwd: Vector3 = s.vel.normalized()
	var turn_amt: float = clamp(side.dot(want) * 2.0, -1.0, 1.0)
	s.turn = lerp(float(s.turn), turn_amt, 1.0 - exp(-delta * 3.0))
	var up: Vector3 = Vector3.UP.rotated(fwd, -s.turn * 0.9)
	node.global_transform = Transform3D(Basis(), pos).looking_at(pos + fwd, up)
	# Shoot when the player is ahead and close.
	s.t_fire -= delta
	if s.t_fire <= 0.0:
		s.t_fire = randf_range(0.9, 1.8) - min(wave, 5) * 0.1
		var d: float = rel.length()
		if d < 950.0 and rel.normalized().dot(fwd) > 0.6:
			_fire_bolt(s, pp)
			if s.hunt > 0.0 and d < 600.0:
				s.t_fire *= 0.5   # hunters fire bursts up close


func _fire_bolt(s: Dictionary, pp: Vector3) -> void:
	var node: MeshInstance3D
	if _bolt_pool.size() > 0:
		node = _bolt_pool.pop_back()
		node.visible = true
	else:
		node = MeshInstance3D.new()
		node.mesh = _bolt_mesh
		node.material_override = _bolt_mat
		add_child(node)
	# Aim at where the player will be, with some spread so it is dodgeable.
	var dist: float = (pp - s.pos).length()
	var lead: Vector3 = pp + aircraft.velocity * (dist / BOLT_SPEED) * 0.8
	var dir: Vector3 = (lead - s.pos).normalized()
	dir = (dir + Vector3(randf_range(-0.06, 0.06), randf_range(-0.04, 0.04), randf_range(-0.06, 0.06))).normalized()
	bolts.append({"node": node, "pos": s.pos + dir * 12.0, "vel": dir * BOLT_SPEED + s.vel * 0.3, "t": 0.0})
	node.global_transform = Transform3D(Basis(), s.pos).looking_at(s.pos + dir, Vector3.UP) * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)


func _step_bolts(delta: float, pp: Vector3) -> void:
	var keep: Array = []
	for b in bolts:
		b.t += delta
		b.pos += b.vel * delta
		var node: MeshInstance3D = b.node
		node.global_position = b.pos
		if b.t > BOLT_LIFE:
			node.visible = false
			_bolt_pool.append(node)
			continue
		if b.pos.distance_to(pp) < BOLT_RADIUS + float(aircraft.spec.radius) * 0.6 and aircraft.alive:
			node.visible = false
			_bolt_pool.append(node)
			player_hit.emit(15.0)
			continue
		keep.append(b)
	bolts = keep


## Damage from the player's guns. Returns true when the ship is destroyed.
func damage(s: Dictionary, amount: float) -> bool:
	s.hp -= amount
	if s.hp > 0.0:
		return false
	kills += 1
	var pos: Vector3 = s.pos
	s.node.queue_free()
	ships.erase(s)
	ship_killed.emit(pos)
	return true


func nearest(from: Vector3, max_dist: float = 4000.0) -> Dictionary:
	var best: Dictionary = {}
	var bd := max_dist
	for s in ships:
		var d: float = s.pos.distance_to(from)
		if d < bd:
			bd = d
			best = s
	return best
