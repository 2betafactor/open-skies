extends CanvasLayer
class_name Hud
## Dogfight HUD, kept out of the way of the scenery: score + combo at the
## top, HP/lives top-left, speed/boost bottom-left, crosshair, lead pip on
## the nearest ship, off-screen arrows to enemies, floating pop-ups.

var aircraft: Aircraft
var tiles: GoogleTiles
var camera: FlightCamera
var enemies: Enemies
var radio: Radio
var main: Node
var outside := false
var place_name := ""
var mobile := false
var score := 0
var combo := 1
var lives := 3
var wave := 1
var hint := ""
var _hint_timer := 0.0
var _pops: Array = []
var _flash := 0.0
var _flash_col := Color.WHITE
var _draw: Control
var _font: Font
var _combo_pulse := 0.0
var _announce := ""
var _announce_t := 0.0

const COL := Color(1.0, 1.0, 1.0, 0.95)
const COL_DIM := Color(1.0, 1.0, 1.0, 0.5)
const COL_GOLD := Color(1.0, 0.85, 0.25)
const COL_RED := Color(1.0, 0.35, 0.3)
const COL_ENEMY := Color(1.0, 0.4, 0.9)
const COL_PANEL := Color(0.0, 0.0, 0.0, 0.3)


func _ready() -> void:
	layer = 5
	_draw = Control.new()
	_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_on_draw)
	add_child(_draw)
	_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	if _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			hint = ""
	for p in _pops:
		p.t += delta
	_pops = _pops.filter(func(p): return p.t < 1.4)
	_flash = max(_flash - delta * 3.0, 0.0)
	_combo_pulse = max(_combo_pulse - delta * 2.5, 0.0)
	_announce_t = max(_announce_t - delta, 0.0)
	_draw.queue_redraw()


func show_hint(text: String, seconds: float = 6.0) -> void:
	hint = text
	_hint_timer = seconds


func announce(text: String, seconds: float = 2.5) -> void:
	_announce = text
	_announce_t = seconds


func pop(text: String, big: bool = false, col: Color = COL_GOLD) -> void:
	_pops.append({"text": text, "t": 0.0, "big": big, "col": col})


func flash(col: Color, amount: float = 0.5) -> void:
	_flash = amount
	_flash_col = col


func combo_pulse() -> void:
	_combo_pulse = 1.0


func _on_draw() -> void:
	if aircraft == null:
		return
	var c := _draw
	var size := c.size
	var cx := size.x * 0.5
	var cy := size.y * 0.5
	var tm := aircraft.telemetry()

	if _flash > 0.0:
		var fc := _flash_col
		fc.a = _flash * 0.35
		c.draw_rect(Rect2(Vector2.ZERO, size), fc)
	if tm.boost > 0.15:
		_draw_speed_lines(c, Vector2(cx, cy), size, tm.boost)

	# Score + combo (top centre).
	var top := 10.0
	c.draw_string(_font, Vector2(cx - 150.0, top + 30.0), "%d" % score, HORIZONTAL_ALIGNMENT_CENTER, 300.0, 30, COL_GOLD)
	if combo > 1:
		var ps := 16 + int(_combo_pulse * 10.0)
		c.draw_string(_font, Vector2(cx + 60.0, top + 28.0), "x%d" % combo, HORIZONTAL_ALIGNMENT_LEFT, -1, ps, COL_GOLD)
	var n_enemies: int = enemies.ships.size() if enemies else 0
	c.draw_string(_font, Vector2(cx - 150.0, top + 46.0), "WAVE %d  ·  %d ship%s" % [wave, n_enemies, "" if n_enemies == 1 else "s"], HORIZONTAL_ALIGNMENT_CENTER, 300.0, 11, COL_DIM)

	# HP + lives (top left).
	var hp: float = clamp(aircraft.hp / 100.0, 0.0, 1.0)
	c.draw_rect(Rect2(16.0, 14.0, 120.0, 8.0), COL_PANEL)
	c.draw_rect(Rect2(16.0, 14.0, 120.0 * hp, 8.0), Color(0.4, 1.0, 0.5) if hp > 0.35 else COL_RED)
	for i in range(lives):
		var lx := 22.0 + i * 18.0
		c.draw_colored_polygon(PackedVector2Array([Vector2(lx, 28.0), Vector2(lx - 6.0, 40.0), Vector2(lx, 37.0), Vector2(lx + 6.0, 40.0)]), COL)
	c.draw_string(_font, Vector2(16.0, 54.0), place_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_DIM)
	if main != null and main.guns != null:
		var n: int = main.guns.rockets
		for i in range(Guns.ROCKET_MAX):
			var rx := 20.0 + i * 14.0
			var col := COL_GOLD if i < n else Color(1, 1, 1, 0.18)
			c.draw_colored_polygon(PackedVector2Array([Vector2(rx, 62.0), Vector2(rx - 3.5, 70.0), Vector2(rx - 3.5, 78.0), Vector2(rx + 3.5, 78.0), Vector2(rx + 3.5, 70.0)]), col)
		c.draw_string(_font, Vector2(16.0 + Guns.ROCKET_MAX * 14.0 + 4.0, 76.0), "ROCKETS" + ("" if mobile else "  E / right-click"), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_DIM)

	# Speed + boost (bottom left; bottom centre-left on phones).
	var bl_y := size.y - (26.0 if mobile else 40.0)
	var bl_x := 18.0 if not mobile else size.x * 0.5 - 60.0
	c.draw_string(_font, Vector2(bl_x, bl_y), "%d" % int(round(tm.airspeed * 3.6)), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, COL)
	c.draw_string(_font, Vector2(bl_x + 56.0, bl_y), "km/h", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_DIM)
	var bw := 110.0
	c.draw_rect(Rect2(bl_x, bl_y + 6.0, bw, 5.0), COL_PANEL)
	c.draw_rect(Rect2(bl_x, bl_y + 6.0, bw * float(tm.boost_energy), 5.0), Color(1.0, 0.6, 0.2) if tm.boost > 0.1 else Color(0.5, 0.9, 1.0))

	# Crosshair where the guns point.
	var aim: Vector3 = aircraft.position + (-aircraft.basis.z) * 900.0
	if camera != null and not camera.is_position_behind(aim):
		var ap := camera.unproject_position(aim)
		c.draw_arc(ap, 9.0, 0.0, TAU, 20, COL, 1.5)
		c.draw_line(ap + Vector2(-16.0, 0.0), ap + Vector2(-10.0, 0.0), COL, 1.5)
		c.draw_line(ap + Vector2(16.0, 0.0), ap + Vector2(10.0, 0.0), COL, 1.5)
	_draw_enemies(c, Vector2(cx, cy), size)
	_draw_radar(c, Vector2(cx, top + 90.0))
	if outside:
		var a := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.01)
		c.draw_string(_font, Vector2(cx - 200.0, cy + 70.0), "RETURN TO THE FIGHT", HORIZONTAL_ALIGNMENT_CENTER, 400.0, 26, Color(COL_RED, a))

	# Warnings and announcements.
	if not is_nan(tm.agl) and tm.agl < 70.0 and tm.vs < -10.0:
		var a := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.015)
		c.draw_string(_font, Vector2(cx - 100.0, cy + 90.0), "PULL UP", HORIZONTAL_ALIGNMENT_CENTER, 200.0, 26, Color(COL_RED, a))
	if _announce_t > 0.0:
		var k: float = min(_announce_t / 0.4, 1.0)
		c.draw_string(_font, Vector2(cx - 250.0, cy - 100.0), _announce, HORIZONTAL_ALIGNMENT_CENTER, 500.0, 40, Color(COL_GOLD, k))
	for p in _pops:
		var k: float = p.t / 1.4
		var col: Color = p.col
		col.a = 1.0 - k * k
		c.draw_string(_font, Vector2(cx - 200.0, cy - 50.0 - k * 70.0), p.text, HORIZONTAL_ALIGNMENT_CENTER, 400.0, 30 if p.big else 20, col)
	if hint != "":
		var hw: float = min(620.0, size.x - 32.0)
		var lines := _font.get_multiline_string_size(hint, HORIZONTAL_ALIGNMENT_CENTER, hw - 16.0, 13).y
		var hy: float = size.y - (120.0 if mobile else 80.0)
		c.draw_rect(Rect2(cx - hw * 0.5, hy - lines, hw, lines + 12.0), COL_PANEL)
		c.draw_multiline_string(_font, Vector2(cx - hw * 0.5 + 8.0, hy + 12.0 - lines + 13.0), hint, HORIZONTAL_ALIGNMENT_CENTER, hw - 16.0, 13, -1, COL)
	if tiles != null:
		var attr := tiles.attribution()
		if attr != "":
			c.draw_string(_font, Vector2(size.x - 16.0 - 420.0, size.y - 6.0), attr, HORIZONTAL_ALIGNMENT_RIGHT, 420.0, 9, Color(1, 1, 1, 0.5))


func _draw_enemies(c: Control, centre: Vector2, size: Vector2) -> void:
	if camera == null or enemies == null:
		return
	var nearest: Dictionary = main.locked if (main != null and not main.locked.is_empty()) else enemies.nearest(aircraft.position, 5000.0)
	for s in enemies.ships:
		var p: Vector3 = s.pos
		var dist: float = aircraft.position.distance_to(p)
		var on_screen := false
		if not camera.is_position_behind(p):
			var sp := camera.unproject_position(p)
			if sp.x > 0.0 and sp.x < size.x and sp.y > 0.0 and sp.y < size.y:
				on_screen = true
				var r: float = clamp(1400.0 / max(dist, 1.0), 12.0, 44.0)
				var col := COL_ENEMY if s != nearest else COL_GOLD
				if s == nearest:
					# Lock bracket: four corners, pulsing.
					var k: float = r + 4.0 + 3.0 * sin(Time.get_ticks_msec() * 0.008)
					var l: float = k * 0.5
					for sx in [-1.0, 1.0]:
						for sy in [-1.0, 1.0]:
							var corner := sp + Vector2(sx * k, sy * k)
							c.draw_line(corner, corner - Vector2(sx * l, 0.0), col, 2.5)
							c.draw_line(corner, corner - Vector2(0.0, sy * l), col, 2.5)
					c.draw_string(_font, sp + Vector2(-50.0, k + 16.0), "%d m" % int(dist), HORIZONTAL_ALIGNMENT_CENTER, 100.0, 13, col)
				else:
					c.draw_rect(Rect2(sp - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), col, false, 1.5)
					c.draw_string(_font, sp + Vector2(-40.0, r + 14.0), "%d m" % int(dist), HORIZONTAL_ALIGNMENT_CENTER, 80.0, 11, col)
				if s == nearest and dist < 1800.0:
					# Lead pip: where the bullets would meet it.
					var t: float = dist / (Guns.SPEED + aircraft.airspeed)
					var lead: Vector3 = p + s.vel * t
					if not camera.is_position_behind(lead):
						var lp := camera.unproject_position(lead)
						c.draw_arc(lp, 6.0, 0.0, TAU, 12, COL_GOLD, 2.0)
		if not on_screen:
			var local: Vector3 = camera.global_transform.affine_inverse() * p
			var dir := Vector2(local.x, -local.y)
			if dir.length() < 1e-3:
				dir = Vector2(0.0, -1.0)
			dir = dir.normalized()
			var q: Vector2 = centre + dir * min(size.x, size.y) * 0.4
			var tip := q + dir * 14.0
			var side := Vector2(-dir.y, dir.x) * 8.0
			c.draw_colored_polygon(PackedVector2Array([tip, q + side, q - side]), COL_ENEMY if s != nearest else COL_GOLD)


## Small radar: enemies around you, relative to your heading (up = ahead).
func _draw_radar(c: Control, centre: Vector2) -> void:
	if enemies == null:
		return
	var rr := 34.0
	c.draw_circle(centre, rr, Color(0, 0, 0, 0.28))
	c.draw_arc(centre, rr, 0.0, TAU, 32, COL_DIM, 1.0)
	c.draw_line(centre + Vector2(0, -rr), centre + Vector2(0, -rr + 6.0), COL_DIM, 1.0)
	c.draw_colored_polygon(PackedVector2Array([centre + Vector2(0, -4), centre + Vector2(-3, 3), centre + Vector2(3, 3)]), COL)
	var range_m := 2500.0
	var nearest: Dictionary = main.locked if (main != null and not main.locked.is_empty()) else {}
	for s in enemies.ships:
		var local: Vector3 = aircraft.basis.inverse() * (s.pos - aircraft.position)
		var v := Vector2(local.x, local.z)   # +z is behind
		var d: float = v.length()
		var p: Vector2 = centre + (v / range_m * rr if d < range_m else v.normalized() * rr)
		c.draw_circle(p, 3.5 if s == nearest else 2.5, COL_GOLD if s == nearest else COL_ENEMY)


func _draw_speed_lines(c: Control, centre: Vector2, size: Vector2, amount: float) -> void:
	var n := 24
	var t := Time.get_ticks_msec() * 0.001
	var rmax: float = max(size.x, size.y) * 0.75
	for i in range(n):
		var a: float = float(i) / n * TAU + sin(t * 3.0 + i) * 0.05
		var r0: float = rmax * (0.4 + 0.25 * fmod(float(i) * 0.37 + t * 2.2, 1.0))
		var r1: float = r0 + rmax * 0.16 * amount
		var d := Vector2(cos(a), sin(a))
		c.draw_line(centre + d * r0, centre + d * r1, Color(1, 1, 1, 0.2 * amount), 2.0)
