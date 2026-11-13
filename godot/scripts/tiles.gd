extends Node3D
class_name GoogleTiles
## Streams Google Photorealistic 3D Tiles (OGC 3D Tiles 1.0) into the scene.
##
## Pure GDScript: tileset traversal with screen-space-error refinement
## (REPLACE semantics — a parent stays visible until all of its children are
## loaded), a small pool of HTTPRequest workers, runtime glTF decoding through
## GLTFDocument, and trimesh collision for the fine tiles near the aircraft.
##
## Google's tiles arrive as plain glTF (float positions, JPEG textures, unlit
## materials). Each tile's node carries a huge ECEF translation, so the JSON
## chunk is rewritten to strip it and the translation is applied in doubles
## via Geo instead — that keeps the 32-bit scene coordinates jitter free.

const ROOT_URL := "https://tile.googleapis.com/v1/3dtiles/root.json"
const TILE_HOST := "https://tile.googleapis.com"

enum { S_NONE, S_QUEUED, S_LOADING, S_LOADED, S_FAILED }

const YUP_TO_ZUP := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))

@export var api_key := ""
@export var max_sse := 24.0           # pixels; lower = sharper, more tiles
@export var workers := 8
@export var max_loaded_tiles := 900
@export var collision_radius := 1800.0
@export var far_distance := 90000.0
@export var select_interval := 0.15

var camera: Camera3D
var focus: Node3D                       # aircraft; drives collision radius
var root_tile: Dictionary = {}
var session := ""
var ready_state := "idle"               # idle | loading | ready | error
var error_text := ""

var _pool: Array[HTTPRequest] = []
var _busy: Dictionary = {}              # HTTPRequest -> tile
var _queue: Array = []                  # tiles wanted but not loaded
var _loaded: Array = []                 # tiles with a scene node
var _visible_now: Dictionary = {}       # tile id -> true
var _select_timer := 0.0
var _epoch := -1
var _ecef_basis := Basis()
var _attribution: Dictionary = {}
var _stats := {"loaded": 0, "visible": 0, "queued": 0, "requests": 0, "failed": 0, "bytes": 0}
var _next_id := 0
var _backoff_until := 0.0

signal tile_loaded(tile: Dictionary)
signal became_ready


func _ready() -> void:
	for i in range(workers):
		var r := HTTPRequest.new()
		r.use_threads = false
		r.timeout = 30.0
		# Browsers already decode gzip; Godot would try to inflate it twice.
		r.accept_gzip = not OS.has_feature("web")
		add_child(r)
		r.request_completed.connect(_on_request_completed.bind(r))
		_pool.append(r)
	Geo.origin_changed.connect(_on_origin_changed)


func start(key: String) -> void:
	api_key = key
	ready_state = "loading"
	var r := _free_worker()
	if r == null:
		return
	var url := "%s?key=%s" % [ROOT_URL, api_key]
	_busy[r] = {"kind": "root"}
	var err := r.request(url)
	if err != OK:
		_busy.erase(r)
		ready_state = "error"
		error_text = "Could not start tile request (%d)" % err


func stats() -> Dictionary:
	_stats["visible"] = _visible_now.size()
	_stats["queued"] = _queue.size()
	_stats["loaded"] = _loaded.size()
	_stats["inflight"] = _busy.size()
	return _stats


func attribution() -> String:
	var names := _attribution.keys()
	names.sort()
	return ", ".join(names)


## 0..1 estimate of how much of the current view is loaded.
func loading_progress() -> float:
	if root_tile.is_empty():
		return 0.0
	var want := _visible_now.size() + _queue.size() + _busy.size()
	if want == 0:
		return 0.0
	return float(_visible_now.size()) / float(want)


# ---------------------------------------------------------------- traversal

func _process(delta: float) -> void:
	if root_tile.is_empty() or camera == null:
		return
	_select_timer -= delta
	if _select_timer <= 0.0:
		_select_timer = select_interval
		_select()
	_pump()


func _select() -> void:
	if Geo.origin_epoch != _epoch:
		_epoch = Geo.origin_epoch
		_ecef_basis = Geo.ecef_basis()
	var vp_h := float(camera.get_viewport().get_visible_rect().size.y)
	var sse_scale := vp_h / (2.0 * tan(deg_to_rad(camera.fov) * 0.5))
	var planes := camera.get_frustum()
	var cam_pos := camera.global_position
	var wanted: Array = []
	var loads: Array = []
	_traverse(root_tile, planes, cam_pos, sse_scale, wanted, loads, 0)

	# Apply visibility.
	var now_visible: Dictionary = {}
	var now := Time.get_ticks_msec() * 0.001
	for t in wanted:
		now_visible[t.id] = true
		t.last_wanted = now
	for t in _loaded:
		var vis: bool = now_visible.has(t.id)
		if t.node.visible != vis:
			t.node.visible = vis
		_update_collision(t, vis)
	_visible_now = now_visible

	# Rebuild the queue: closest / coarsest first.
	loads.sort_custom(func(a, b): return a.priority < b.priority)
	_queue.clear()
	for t in loads:
		if t.state == S_NONE or t.state == S_QUEUED:
			t.state = S_QUEUED
			_queue.append(t)
	# Anything previously queued but no longer wanted goes back to idle.
	# (Cheap: tiles not in `loads` keep S_QUEUED harmlessly until wanted again.)
	_evict(now)
	_refresh_attribution(wanted)


func _traverse(t: Dictionary, planes: Array, cam: Vector3, sse_scale: float, wanted: Array, loads: Array, depth: int) -> void:
	_ensure_local(t)
	if _culled(t, planes):
		return
	var dist := _distance(t, cam)
	if dist > far_distance:
		return
	var sse: float = t.ge * sse_scale / max(dist, 1.0)
	var refine := sse > max_sse

	if refine and t.sub_uri != "" and not t.sub_loaded:
		# External subtree must be fetched before we know the children.
		t.priority = dist
		if t.sub_state == S_NONE:
			t.sub_state = S_QUEUED
		if t.sub_state != S_LOADING:
			loads.append(t)
		_want_self(t, wanted, loads, dist)
		return

	if refine and t.children.size() > 0:
		# REPLACE refinement: children replace the parent only once every
		# visible child is loaded, else keep showing the parent.
		var all_ready := true
		for c in t.children:
			_ensure_local(c)
			if _culled(c, planes):
				continue
			if _distance(c, cam) > far_distance:
				continue
			if c.uri == "" or c.state == S_LOADED:
				continue
			all_ready = false
			c.priority = _distance(c, cam) + depth
			if c.state != S_LOADING:
				loads.append(c)
		if all_ready:
			for c in t.children:
				_traverse(c, planes, cam, sse_scale, wanted, loads, depth + 1)
			return
		_want_self(t, wanted, loads, dist)
		return

	_want_self(t, wanted, loads, dist)
	if not refine:
		return
	# Leaf with nothing finer: nothing more to do.


func _want_self(t: Dictionary, wanted: Array, loads: Array, dist: float) -> void:
	if t.uri == "":
		return
	if t.state == S_LOADED:
		wanted.append(t)
	else:
		t.priority = dist
		if t.state != S_LOADING:
			loads.append(t)


func _ensure_local(t: Dictionary) -> void:
	if t.epoch == _epoch:
		return
	t.epoch = _epoch
	var b: Array = t.box
	t.lc = Geo.ecef_to_local(b[0], b[1], b[2])
	var axes: Array = []
	var half: Array = []
	for k in range(3):
		var v := Vector3(b[3 + 3 * k], b[4 + 3 * k], b[5 + 3 * k])
		var len := v.length()
		var lv := Geo.ecef_dir_to_local(v.x, v.y, v.z)
		axes.append(lv / len if len > 0.0 else Vector3.ZERO)
		half.append(len)
	t.lax = axes
	t.lhalf = half
	t.radius = sqrt(half[0] * half[0] + half[1] * half[1] + half[2] * half[2])
	if t.has("node") and t.node != null:
		_place_node(t)


func _culled(t: Dictionary, planes: Array) -> bool:
	var c: Vector3 = t.lc
	var r: float = t.radius
	# Tiles around the aircraft are never culled: they carry the collision
	# geometry (ground height, crashes) even when the camera looks elsewhere.
	if focus != null and c.distance_to(focus.global_position) < collision_radius + r:
		return false
	# Sphere test first (cheap), then the 8 OBB corners.
	for p in planes:
		var d: float = p.distance_to(c)
		if d > r:
			return true
	if r < 200.0:
		return false
	var ax: Array = t.lax
	var hh: Array = t.lhalf
	for p in planes:
		var all_out := true
		for i in range(8):
			var corner: Vector3 = c \
				+ ax[0] * (hh[0] if (i & 1) else -hh[0]) \
				+ ax[1] * (hh[1] if (i & 2) else -hh[1]) \
				+ ax[2] * (hh[2] if (i & 4) else -hh[2])
			if not p.is_point_over(corner):
				all_out = false
				break
		if all_out:
			return true
	return false


func _distance(t: Dictionary, cam: Vector3) -> float:
	var d: Vector3 = cam - t.lc
	var closest: Vector3 = t.lc
	var ax: Array = t.lax
	var hh: Array = t.lhalf
	for k in range(3):
		var a: Vector3 = ax[k]
		var proj: float = clamp(d.dot(a), -hh[k], hh[k])
		closest += a * proj
	return cam.distance_to(closest)


# ------------------------------------------------------------------ loading

func _free_worker() -> HTTPRequest:
	for r in _pool:
		if not _busy.has(r):
			return r
	return null


func _pump() -> void:
	var now := Time.get_ticks_msec() * 0.001
	if now < _backoff_until:
		return
	while _queue.size() > 0:
		var r := _free_worker()
		if r == null:
			return
		var t: Dictionary = _queue.pop_front()
		var is_sub: bool = t.sub_uri != "" and not t.sub_loaded
		if is_sub:
			if t.sub_state == S_LOADING:
				continue
			t.sub_state = S_LOADING
		else:
			if t.state != S_QUEUED:
				continue
			t.state = S_LOADING
		var uri: String = t.sub_uri if is_sub else t.uri
		var url := _full_url(uri)
		_busy[r] = {"kind": "sub" if is_sub else "tile", "tile": t}
		_stats["requests"] += 1
		var err := r.request(url)
		if err != OK:
			_busy.erase(r)
			if is_sub:
				t.sub_state = S_NONE
			else:
				t.state = S_FAILED
				_stats["failed"] += 1


func _full_url(uri: String) -> String:
	var url := uri if uri.begins_with("http") else TILE_HOST + uri
	url += "&" if "?" in url else "?"
	url += "key=" + api_key
	if session != "" and not ("session=" in url):
		url += "&session=" + session
	return url


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, r: HTTPRequest) -> void:
	var job: Dictionary = _busy.get(r, {})
	_busy.erase(r)
	if job.is_empty():
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_stats["failed"] += 1
		if code == 429 or code == 503:
			_backoff_until = Time.get_ticks_msec() * 0.001 + 2.0
		if job.kind == "root":
			ready_state = "error"
			error_text = "Tile API error (HTTP %d, result %d). Check the Google Maps key and that Map Tiles API is enabled." % [code, result]
			push_error(error_text)
			return
		var t: Dictionary = job.tile
		if job.kind == "sub":
			t.sub_state = S_NONE
		else:
			t.state = S_FAILED if code == 404 else S_NONE
		return
	_stats["bytes"] += body.size()
	match job.kind:
		"root":
			_parse_root(body)
		"sub":
			_parse_subtree(job.tile, body)
		"tile":
			_build_tile(job.tile, body)


func _parse_root(body: PackedByteArray) -> void:
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		ready_state = "error"
		error_text = "Bad tileset JSON"
		return
	var data: Dictionary = json.data
	root_tile = _make_tile(data.get("root", {}), 0)
	ready_state = "ready"
	became_ready.emit()


func _parse_subtree(t: Dictionary, body: PackedByteArray) -> void:
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		t.sub_state = S_FAILED
		return
	var root: Dictionary = json.data.get("root", {})
	var sub := _make_tile(root, t.depth)
	t.children = sub.children
	t.ge = sub.ge
	t.uri = sub.uri
	t.sub_loaded = true
	t.sub_state = S_LOADED
	if sub.sub_uri != "":
		# A subtree whose root is itself another subtree (rare): chain it.
		t.sub_uri = sub.sub_uri
		t.sub_loaded = false
		t.sub_state = S_NONE


func _make_tile(src: Dictionary, depth: int) -> Dictionary:
	var box: Array = src.get("boundingVolume", {}).get("box", [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1])
	var uri: String = src.get("content", {}).get("uri", "")
	if session == "" and "session=" in uri:
		session = uri.split("session=")[1].split("&")[0]
	var t := {
		"id": _next_id,
		"box": box,
		"ge": float(src.get("geometricError", 0.0)),
		"uri": "",
		"sub_uri": "",
		"sub_loaded": true,
		"sub_state": S_NONE,
		"children": [],
		"state": S_NONE,
		"node": null,
		"epoch": -1,
		"lc": Vector3.ZERO,
		"lax": [],
		"lhalf": [],
		"radius": 0.0,
		"priority": 0.0,
		"last_wanted": 0.0,
		"depth": depth,
		"placements": [],
		"collision": null,
		"copyright": "",
	}
	_next_id += 1
	if uri.split("?")[0].ends_with(".json"):
		t.sub_uri = uri
		t.sub_loaded = false
	else:
		t.uri = uri
	for c in src.get("children", []):
		t.children.append(_make_tile(c, depth + 1))
	return t


# ------------------------------------------------------------- glTF decode

func _build_tile(t: Dictionary, body: PackedByteArray) -> void:
	var rewritten := _strip_translations(body)
	if rewritten.is_empty():
		t.state = S_FAILED
		_stats["failed"] += 1
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_buffer(rewritten.bytes, "", state)
	if err != OK:
		t.state = S_FAILED
		_stats["failed"] += 1
		push_warning("glTF decode failed for tile %d: %s" % [t.id, error_string(err)])
		return
	var scene := doc.generate_scene(state)
	if scene == null:
		t.state = S_FAILED
		_stats["failed"] += 1
		return
	# Materials: unlit, mipmapped, fog-friendly.
	var meshes: Array = []
	_prepare_meshes(scene, meshes)
	t.meshes = meshes
	t.placements = rewritten.placements
	t.copyright = rewritten.copyright
	var holder := Node3D.new()
	holder.name = "tile_%d" % t.id
	holder.add_child(scene)
	add_child(holder)
	t.node = holder
	t.scene = scene
	_place_node(t)
	holder.visible = false
	t.state = S_LOADED
	_loaded.append(t)
	for part: String in rewritten.copyright.split(";"):
		var s := part.strip_edges()
		if s != "":
			_attribution[s] = _attribution.get(s, 0)
	tile_loaded.emit(t)
	# A freshly loaded tile may complete a sibling set; reselect soon.
	_select_timer = min(_select_timer, 0.05)


## Parse the GLB, zero every scene-root node translation and remember it in
## doubles. Returns {bytes, placements:[{t:[x,y,z], basis:Basis}], copyright}.
func _strip_translations(glb: PackedByteArray) -> Dictionary:
	if glb.size() < 20 or glb.decode_u32(0) != 0x46546C67:
		return {}
	var json_len := glb.decode_u32(12)
	var json_text := glb.slice(20, 20 + json_len).get_string_from_utf8()
	var json := JSON.new()
	if json.parse(json_text) != OK:
		return {}
	var g: Dictionary = json.data
	var nodes: Array = g.get("nodes", [])
	var scene_idx: int = g.get("scene", 0)
	var scenes: Array = g.get("scenes", [])
	var roots: Array = scenes[scene_idx].get("nodes", []) if scenes.size() > scene_idx else range(nodes.size())
	var placements: Array = []
	for ni in roots:
		var n: Dictionary = nodes[ni]
		var tr := [0.0, 0.0, 0.0]
		var basis := Basis()
		if n.has("matrix"):
			var m: Array = n.matrix
			tr = [float(m[12]), float(m[13]), float(m[14])]
			basis = Basis(Vector3(m[0], m[1], m[2]), Vector3(m[4], m[5], m[6]), Vector3(m[8], m[9], m[10]))
			m[12] = 0.0
			m[13] = 0.0
			m[14] = 0.0
			n.matrix = m
		else:
			if n.has("translation"):
				var tv: Array = n.translation
				tr = [float(tv[0]), float(tv[1]), float(tv[2])]
				n.erase("translation")
			if n.has("rotation"):
				var q: Array = n.rotation
				basis = Basis(Quaternion(q[0], q[1], q[2], q[3]))
			if n.has("scale"):
				var s: Array = n.scale
				basis = basis.scaled(Vector3(s[0], s[1], s[2]))
		placements.append({"t": tr, "basis": basis})
	var new_json := JSON.stringify(g)
	var jb := new_json.to_utf8_buffer()
	while jb.size() % 4 != 0:
		jb.append(0x20)
	var out := PackedByteArray()
	out.resize(12)
	out.encode_u32(0, 0x46546C67)
	out.encode_u32(4, 2)
	var rest := glb.slice(20 + json_len)
	out.encode_u32(8, 12 + 8 + jb.size() + rest.size())
	var ch := PackedByteArray()
	ch.resize(8)
	ch.encode_u32(0, jb.size())
	ch.encode_u32(4, 0x4E4F534A)
	out.append_array(ch)
	out.append_array(jb)
	out.append_array(rest)
	return {"bytes": out, "placements": placements, "copyright": str(g.get("asset", {}).get("copyright", ""))}


func _prepare_meshes(node: Node, meshes: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh != null:
			meshes.append(mi)
			for si in range(mesh.get_surface_count()):
				var mat := mesh.surface_get_material(si)
				if mat is BaseMaterial3D:
					var bm := mat as BaseMaterial3D
					bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					bm.cull_mode = BaseMaterial3D.CULL_BACK
					bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
					bm.vertex_color_use_as_albedo = false
					var tex := bm.albedo_texture
					if tex is ImageTexture:
						var img: Image = tex.get_image()
						if img != null and not img.has_mipmaps():
							img.generate_mipmaps()
							bm.albedo_texture = ImageTexture.create_from_image(img)
	for c in node.get_children():
		_prepare_meshes(c, meshes)


func _place_node(t: Dictionary) -> void:
	var scene: Node = t.get("scene")
	if scene == null:
		return
	var kids := scene.get_children()
	var placements: Array = t.placements
	for i in range(min(kids.size(), placements.size())):
		var k = kids[i]
		if not (k is Node3D):
			continue
		var p: Dictionary = placements[i]
		# glTF content is Y-up; 3D Tiles applies an implicit Y-up -> Z-up
		# (ECEF) rotation: (x, y, z) -> (x, -z, y), translation included.
		var pos := Geo.ecef_to_local(p.t[0], -p.t[2], p.t[1])
		var basis: Basis = _ecef_basis * YUP_TO_ZUP * p.basis
		(k as Node3D).transform = Transform3D(basis, pos)


func _on_origin_changed() -> void:
	# Local caches refresh lazily through _ensure_local (epoch mismatch);
	# nodes are re-placed there as well. Force an immediate pass so nothing
	# renders in the stale frame.
	_epoch = Geo.origin_epoch
	_ecef_basis = Geo.ecef_basis()
	for t in _loaded:
		t.epoch = -1
		_ensure_local(t)
	_select_timer = 0.0


# --------------------------------------------------------------- collision

func _update_collision(t: Dictionary, vis: bool) -> void:
	if focus == null:
		return
	# Only reasonably fine tiles (ge < 150 m) carry collision: the coarse
	# globe tiles are hundreds of metres off and would place the spawn
	# underground.
	var near: bool = vis and t.ge < 150.0 and t.lc.distance_to(focus.global_position) < collision_radius + t.radius
	if near and t.collision == null:
		var bodies: Array = []
		for mi in t.meshes:
			var m: MeshInstance3D = mi
			if m.mesh == null:
				continue
			var shape := m.mesh.create_trimesh_shape()
			if shape == null:
				continue
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			m.add_child(body)  # trimesh is in the mesh's own space
			bodies.append(body)
		t.collision = bodies  # may be empty: nothing to collide with, don't retry
	elif t.collision is Array:
		for body in t.collision:
			var b: StaticBody3D = body
			if b.process_mode == (Node.PROCESS_MODE_INHERIT if near else Node.PROCESS_MODE_DISABLED):
				continue
			b.process_mode = Node.PROCESS_MODE_INHERIT if near else Node.PROCESS_MODE_DISABLED
			for cs in b.get_children():
				if cs is CollisionShape3D:
					cs.disabled = not near


## Terrain height (local Y) under a local XZ position, or NAN if no collision
## geometry is loaded there yet.
func ground_height(pos: Vector3, max_h: float = 12000.0) -> float:
	var space := get_world_3d().direct_space_state
	var from := Vector3(pos.x, max_h, pos.z)
	var to := Vector3(pos.x, -1000.0, pos.z)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return NAN
	return hit.position.y


func debug_collision(at: Vector3) -> Dictionary:
	var n_bodies := 0
	var n_enabled := 0
	var nearest := INF
	var sample := {}
	var space := get_world_3d().direct_space_state
	for t in _loaded:
		if not (t.collision is Array):
			continue
		for b in t.collision:
			n_bodies += 1
			var body: StaticBody3D = b
			var cs: CollisionShape3D = body.get_child(0)
			if cs.disabled or body.process_mode == Node.PROCESS_MODE_DISABLED:
				continue
			n_enabled += 1
			var faces := (cs.shape as ConcavePolygonShape3D).get_faces()
			var aabb := AABB(faces[0], Vector3.ZERO)
			for f in faces:
				aabb = aabb.expand(f)
			var centre_g: Vector3 = body.global_transform * aabb.get_center()
			var d: float = centre_g.distance_to(at)
			if d < nearest:
				nearest = d
				var q := PhysicsRayQueryParameters3D.create(centre_g + Vector3(0, 3000, 0), centre_g + Vector3(0, -3000, 0), 1)
				var hit := space.intersect_ray(q)
				sample = {"centre_g": centre_g, "faces": faces.size() / 3, "vis": _visible_now.has(t.id), "ge": t.ge, "ray_hit": hit.get("position", null), "body_gpos": body.global_position, "mesh_gpos": (body.get_parent() as Node3D).global_position, "in_tree": body.is_inside_tree(), "layer": body.collision_layer}
	return {"bodies": n_bodies, "enabled": n_enabled, "nearest_enabled_centre": nearest, "sample": sample}


# ---------------------------------------------------------------- eviction

func _evict(now: float) -> void:
	if _loaded.size() <= max_loaded_tiles:
		return
	var candidates: Array = []
	for t in _loaded:
		if not _visible_now.has(t.id):
			candidates.append(t)
	candidates.sort_custom(func(a, b): return a.last_wanted < b.last_wanted)
	var excess := _loaded.size() - int(max_loaded_tiles * 0.85)
	for t in candidates:
		if excess <= 0:
			break
		if now - t.last_wanted < 5.0:
			break
		_unload(t)
		excess -= 1


func _unload(t: Dictionary) -> void:
	if t.node != null:
		t.node.queue_free()
	t.node = null
	t.scene = null
	t.meshes = []
	t.collision = null
	t.state = S_NONE
	_loaded.erase(t)


func _refresh_attribution(wanted: Array) -> void:
	var seen: Dictionary = {}
	for t in wanted:
		for part: String in str(t.copyright).split(";"):
			var s := part.strip_edges()
			if s != "":
				seen[s] = true
	if seen.size() > 0:
		_attribution = seen
