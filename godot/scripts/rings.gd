extends Node3D
class_name RingCourse
## Arcade ring course: a chain of glowing rings laid out ahead of the aircraft
## that bends gently left/right/up/down. Flying through one scores points and
## builds a combo; missing one breaks it. The course keeps regenerating so
## there is always something to chase.

const RING_RADIUS := 40.0
const SPACING := 420.0
const COUNT := 12

var aircraft: Aircraft
var tiles: GoogleTiles
var rings: Array = []          # [{node, pos, dir, passed}]
var score := 0
var combo := 0
var best_combo := 0
var rings_hit := 0
var rings_missed := 0
var active := false
var _mesh: Mesh
var _mat_next: StandardMaterial3D
var _mat_far: StandardMaterial3D
var _mat_hit: StandardMaterial3D
var _next_index := 0

signal ring_passed(points: int, combo: int)
signal ring_missed


func _ready() -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = RING_RADIUS - 3.0
	tm.outer_radius = RING_RADIUS
	tm.rings = 24
	tm.ring_segments = 12
	_mesh = tm
	_mat_next = _make_mat(Color(1.0, 0.85, 0.2), 2.5)
	_mat_far = _make_mat(Color(0.35, 0.9, 1.0), 1.2)
	_mat_hit = _make_mat(Color(0.4, 1.0, 0.5), 2.0)


func _make_mat(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func start() -> void:
	clear()
	score = 0
	combo = 0
	best_combo = 0
	rings_hit = 0
	rings_missed = 0
	active = true
	_next_index = 0
	var pos: Vector3 = aircraft.position + (-aircraft.basis.z) * 500.0
	var dir: Vector3 = -aircraft.basis.z
	dir.y = 0.0
	dir = dir.normalized()
	for i in range(COUNT):
		_add_ring(pos, dir)
		var step := _advance(pos, dir)
		pos = step[0]
		dir = step[1]


func clear() -> void:
	for r in rings:
		r.node.queue_free()
	rings.clear()
	active = false


## Next position/direction: wander in heading, gentle altitude changes, and
## stay a sane height above whatever terrain we know about.
func _advance(pos: Vector3, dir: Vector3) -> Array:
	var turn := randf_range(-0.22, 0.22)
	var ndir := dir.rotated(Vector3.UP, turn)
	var npos := pos + ndir * SPACING
	npos.y += randf_range(-60.0, 70.0)
	if tiles != null:
		var g := tiles.ground_height(npos)
		if not is_nan(g):
			npos.y = max(npos.y, g + 180.0)
	npos.y = max(npos.y, 120.0)
	return [npos, ndir]


func _add_ring(pos: Vector3, dir: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = _mat_far
	add_child(mi)
	mi.global_position = pos
	# Torus axis is Y; point it along the flight direction.
	var t := Transform3D(Basis(), pos).looking_at(pos + dir, Vector3.UP)
	mi.global_transform = t * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
	rings.append({"node": mi, "pos": pos, "dir": dir, "passed": false, "missed": false})


func _process(delta: float) -> void:
	if not active or aircraft == null or rings.is_empty():
		return
	# Only the next ring counts; the others glow softly.
	var nxt: Dictionary = rings[0]
	var mi: MeshInstance3D = nxt.node
	if mi.material_override != _mat_next:
		mi.material_override = _mat_next
	mi.rotate_object_local(Vector3.UP, delta * 1.5)
	var p: Vector3 = aircraft.position
	var rel: Vector3 = p - nxt.pos
	var along: float = rel.dot(nxt.dir)
	var lateral: float = (rel - nxt.dir * along).length()
	if along > 0.0:
		# Crossed the ring plane this frame.
		if lateral < RING_RADIUS + 6.0:
			_hit(nxt)
		else:
			_miss(nxt)
	elif along > -SPACING * 1.5 and rel.length() > SPACING * 2.5:
		# Wandered off far behind / beside: skip it.
		_miss(nxt)


func _hit(r: Dictionary) -> void:
	combo += 1
	best_combo = max(best_combo, combo)
	rings_hit += 1
	var pts: int = 100 * min(combo, 10)
	score += pts
	(r.node as MeshInstance3D).material_override = _mat_hit
	ring_passed.emit(pts, combo)
	_retire(r)


func _miss(r: Dictionary) -> void:
	combo = 0
	rings_missed += 1
	ring_missed.emit()
	_retire(r)


func _retire(r: Dictionary) -> void:
	rings.pop_front()
	var node: MeshInstance3D = r.node
	# Fade out quickly, then extend the course at the far end.
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector3.ONE * 0.1, 0.6)
	tw.tween_callback(node.queue_free)
	var last: Dictionary = rings[-1] if rings.size() > 0 else r
	var step := _advance(last.pos, last.dir)
	_add_ring(step[0], step[1])


func next_ring_position() -> Vector3:
	return rings[0].pos if rings.size() > 0 else Vector3.ZERO
