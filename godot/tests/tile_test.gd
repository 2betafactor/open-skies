extends Node3D
## Headless check: stream tiles around a city and report what loaded.
## Run: godot --headless --path godot tests/tile_test.tscn -- --key=KEY [--lat= --lon=] [--seconds=25]

var tiles: GoogleTiles
var cam: Camera3D
var t := 0.0
var seconds := 25.0
var lat := 37.7897
var lon := -122.4017
var done := false


func _ready() -> void:
	var key := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--key="): key = a.substr(6)
		if a.begins_with("--lat="): lat = float(a.substr(6))
		if a.begins_with("--lon="): lon = float(a.substr(6))
		if a.begins_with("--seconds="): seconds = float(a.substr(10))
	if key == "":
		var f := FileAccess.open("res://../config.js", FileAccess.READ)
		if f:
			var m := RegEx.new(); m.compile("AIza[A-Za-z0-9_-]+")
			var r := m.search(f.get_as_text())
			if r: key = r.get_string()
	print("key present: ", key != "", " lat/lon ", lat, " ", lon)
	Geo.set_origin(lat, lon, 0.0)
	var e := Geo.geodetic_to_ecef(lat, lon, 0.0)
	var back := Geo.ecef_to_geodetic(e[0], e[1], e[2])
	print("geo roundtrip: ", back, " local of origin: ", Geo.ecef_arr_to_local(e))
	print("1km north local: ", Geo.geodetic_to_local(lat + 0.009, lon, 0.0))
	cam = Camera3D.new()
	cam.fov = 60
	cam.near = 2.0
	cam.far = 100000.0
	add_child(cam)
	cam.position = Vector3(0, 500, 0)
	cam.look_at(Vector3(0, 0, -1500), Vector3.UP)
	cam.current = true
	var focus := Node3D.new()
	add_child(focus)
	focus.position = Vector3(0, 300, 0)
	tiles = GoogleTiles.new()
	tiles.camera = cam
	tiles.focus = focus
	tiles.max_sse = 24
	add_child(tiles)
	tiles.start(key)


func _process(delta: float) -> void:
	t += delta
	if int(t * 5) != int((t - delta) * 5) and int(t) % 5 == 0 and int(t) != int(t - delta):
		var s := tiles.stats()
		print("t=%.0f state=%s loaded=%d visible=%d queued=%d inflight=%d req=%d failed=%d bytes=%d progress=%.2f" % [t, tiles.ready_state, s.loaded, s.visible, s.queued, s.inflight, s.requests, s.failed, s.bytes, tiles.loading_progress()])
	if t > seconds and not done:
		done = true
		_report()
		get_tree().quit()


func _report() -> void:
	var s := tiles.stats()
	print("FINAL state=%s loaded=%d visible=%d queued=%d req=%d failed=%d bytes=%d" % [tiles.ready_state, s.loaded, s.visible, s.queued, s.requests, s.failed, s.bytes])
	print("attribution: ", tiles.attribution())
	var ges := []
	var ys := []
	var n := 0
	for tile in tiles._loaded:
		if tiles._visible_now.has(tile.id):
			ges.append(tile.ge)
			var kids: Array = tile.scene.get_children()
			if kids.size() > 0:
				ys.append(snapped(kids[0].position.y, 0.1))
			n += 1
	ges.sort()
	print("visible tiles: ", n, " geometric errors (min/median/max): ", ges[0] if ges else null, " ", ges[ges.size() / 2] if ges else null, " ", ges[-1] if ges else null)
	ys.sort()
	print("visible node heights sample: ", ys.slice(0, 5), " ... ", ys.slice(max(0, ys.size() - 5)))
	# Ground probe under the origin: needs collision bodies.
	var g := tiles.ground_height(Vector3(0, 0, 0))
	print("ground height at origin: ", g)
	print("ground at 500m north: ", tiles.ground_height(Vector3(0, 0, -500)))
