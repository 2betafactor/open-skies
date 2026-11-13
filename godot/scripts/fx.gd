extends Node3D
class_name Fx
## Visual juice: ring bursts, crash explosion, afterburner flames, wingtip
## trails. CPU particles so it runs on the Compatibility renderer and phones.

var aircraft: Aircraft
var _burst_pool: Array[CPUParticles3D] = []
var _boom: CPUParticles3D
var _flames: Array[MeshInstance3D] = []
var _trails: Array[CPUParticles3D] = []
var _flame_mat: StandardMaterial3D


func _ready() -> void:
	for i in range(4):
		var p := _make_burst()
		add_child(p)
		_burst_pool.append(p)
	_boom = _make_boom()
	add_child(_boom)
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.albedo_color = Color(1.0, 0.55, 0.15, 0.85)
	_flame_mat.emission_enabled = true
	_flame_mat.emission = Color(1.0, 0.5, 0.1)
	_flame_mat.emission_energy_multiplier = 3.0
	_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func attach(ac: Aircraft) -> void:
	aircraft = ac
	for f in _flames:
		f.queue_free()
	_flames.clear()
	for t in _trails:
		t.queue_free()
	_trails.clear()
	var spec := ac.spec
	var r: float = spec.radius
	# Afterburner cones at the tail.
	var nozzles: Array = spec.get("nozzles", [Vector3(0.0, 0.0, r * 0.95)])
	for n in nozzles:
		var mi := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.45
		cone.bottom_radius = 0.05
		cone.height = 6.0
		cone.radial_segments = 10
		mi.mesh = cone
		mi.material_override = _flame_mat
		mi.rotation_degrees.x = -90.0
		mi.position = n + Vector3(0, 0, 3.0)
		mi.scale = Vector3(0.001, 0.001, 0.001)
		ac.add_child(mi)
		_flames.append(mi)
	# Wingtip trails.
	for sx in [-1.0, 1.0]:
		var t := CPUParticles3D.new()
		t.amount = 60
		t.lifetime = 1.4
		t.emitting = false
		t.local_coords = false
		t.direction = Vector3.ZERO
		t.spread = 0.0
		t.initial_velocity_min = 0.0
		t.initial_velocity_max = 0.0
		t.gravity = Vector3.ZERO
		t.scale_amount_min = 0.6
		t.scale_amount_max = 1.0
		var qm := QuadMesh.new()
		qm.size = Vector2(1.2, 1.2)
		t.mesh = qm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1, 1, 1, 0.35)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.vertex_color_use_as_albedo = true
		t.mesh.surface_set_material(0, m)
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.5))
		g.set_color(1, Color(1, 1, 1, 0.0))
		t.color_ramp = g
		t.position = Vector3(sx * float(spec.span) * 0.48, 0.0, 0.2)
		ac.add_child(t)
		_trails.append(t)


func _make_burst() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 48
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 25.0
	p.initial_velocity_max = 60.0
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	p.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.9, 0.3)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.8, 0.2)
	m.emission_energy_multiplier = 2.0
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.surface_set_material(0, m)
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.5, 1.0))
	g.set_color(1, Color(1.0, 0.5, 0.1, 0.0))
	p.color_ramp = g
	return p


func _make_boom() -> CPUParticles3D:
	var p := _make_burst()
	p.amount = 140
	p.lifetime = 1.8
	p.initial_velocity_min = 15.0
	p.initial_velocity_max = 70.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 9.0
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.8, 0.3, 1.0))
	g.add_point(0.3, Color(1.0, 0.3, 0.05, 0.9))
	g.set_color(1, Color(0.15, 0.15, 0.15, 0.0))
	p.color_ramp = g
	return p


func burst(at: Vector3, big: bool = false) -> void:
	for p in _burst_pool:
		if not p.emitting:
			p.global_position = at
			p.amount = 90 if big else 48
			p.restart()
			p.emitting = true
			return


func explode(at: Vector3) -> void:
	_boom.global_position = at
	_boom.restart()
	_boom.emitting = true


func _process(delta: float) -> void:
	if aircraft == null:
		return
	var boost: float = aircraft.boost
	var thr: float = aircraft.throttle
	var flame: float = clamp(boost * 1.2 + (thr - 0.7) * 0.5, 0.0, 1.3)
	var flicker := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.05)
	for f in _flames:
		var s: float = max(flame * flicker, 0.001)
		f.scale = Vector3(s, s * (0.8 + 0.6 * boost), s)
	var trail_on: bool = boost > 0.3 or abs(aircraft.g_load) > 2.2
	for t in _trails:
		if t.emitting != trail_on:
			t.emitting = trail_on
