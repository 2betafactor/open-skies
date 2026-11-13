extends SceneTree
## Times the per-tile work: glb rewrite, GLTFDocument decode, mipmaps, trimesh.
func _init() -> void:
	var f := FileAccess.open("/tmp/claude-1000/-home-exedev/dabe6a36-c90f-42da-826a-04892fabd47c/scratchpad/deep.glb", FileAccess.READ)
	var glb := f.get_buffer(f.get_length())
	var tiles := GoogleTiles.new()
	root.add_child(tiles)
	var t0 := Time.get_ticks_usec()
	var rw := tiles._strip_translations(glb)
	var t1 := Time.get_ticks_usec()
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_buffer(rw.bytes, "", st)
	var scene := doc.generate_scene(st)
	var t2 := Time.get_ticks_usec()
	var meshes := []
	tiles._prepare_meshes(scene, meshes)
	var t3 := Time.get_ticks_usec()
	var shape = (meshes[0] as MeshInstance3D).mesh.create_trimesh_shape()
	var t4 := Time.get_ticks_usec()
	print("glb %d B: rewrite %.1f ms, decode %.1f ms, materials+mips %.1f ms, trimesh %.1f ms" % [glb.size(), (t1-t0)/1000.0, (t2-t1)/1000.0, (t3-t2)/1000.0, (t4-t3)/1000.0])
	quit()
