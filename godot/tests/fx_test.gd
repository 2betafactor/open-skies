extends Node3D
## Visual check for particle materials: run under Xvfb with --shot=path.
var t := 0.0
var fx: Fx
func _ready() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 0, 0)
	cam.current = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.3, 0.5, 0.8)
	env.environment = e
	add_child(env)
	fx = Fx.new()
	add_child(fx)
	var variant := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--variant="):
			variant = a.substr(10)
	for c in fx.get_children():
		if c is CPUParticles3D:
			var m: StandardMaterial3D = (c as CPUParticles3D).mesh.material
			match variant:
				"notex": m.albedo_texture = null
				"mix": m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
				"notexmix":
					m.albedo_texture = null
					m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
				"basecolor":
					(c as CPUParticles3D).color = Color(1.0, 0.2, 0.2)
					(c as CPUParticles3D).color_ramp = null
	fx.burst(Vector3(-8, 0, -30))
	fx.explode(Vector3(8, 0, -40))
func _process(delta: float) -> void:
	t += delta
	if t > 0.5:
		var shot := ""
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--shot="):
				shot = a.substr(7)
		if shot != "":
			get_viewport().get_texture().get_image().save_png(shot)
			print("saved ", shot)
		get_tree().quit()
