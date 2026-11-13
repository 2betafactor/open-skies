extends CanvasLayer
class_name Hud
## Arcade HUD: time, score, combo, speed, boost, next-ring pointer, floating
## score pop-ups, speed lines when boosting. No instruments.

var aircraft: Aircraft
var tiles: GoogleTiles
var camera: FlightCamera
var rings: RingCourse
var radio: Radio
var place_name := ""
var mobile := false
var time_left := 0.0
var timed := true
var hint := ""
var _hint_timer := 0.0
var _pops: Array = []          # [{text, t, big, col}]
var _flash := 0.0
var _flash_col := Color.WHITE
var _draw: Control
var _font: Font
var _combo_pulse := 0.0

const COL := Color(1.0, 1.0, 1.0, 0.95)
const COL_DIM := Color(1.0, 1.0, 1.0, 0.55)
const COL_GOLD := Color(1.0, 0.85, 0.25)
const COL_RED := Color(1.0, 0.35, 0.3)
const COL_PANEL := Color(0.0, 0.0, 0.0, 0.35)


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
	_draw.queue_redraw()


func show_hint(text: String, seconds: float = 6.0) -> void:
	hint = text
	_hint_timer = seconds


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

	# Time + score (top centre).
	var top := 12.0 if not mobile else 8.0
	if timed:
		var secs: int = int(ceil(time_left))
		var tcol := COL if time_left > 10.0 else (COL_RED if int(time_left * 4.0) % 2 == 0 else COL)
		c.draw_string(_font, Vector2(cx - 120.0, top + 40.0), "%d" % secs, HORIZONTAL_ALIGNMENT_CENTER, 240.0, 44, tcol)
		c.draw_string(_font, Vector2(cx - 120.0, top + 58.0), "SECONDS", HORIZONTAL_ALIGNMENT_CENTER, 240.0, 11, COL_DIM)
		top += 62.0
	if rings != null:
		c.draw_string(_font, Vector2(cx - 150.0, top + 26.0), "%d" % rings.score, HORIZONTAL_ALIGNMENT_CENTER, 300.0, 26, COL_GOLD)
		c.draw_string(_font, Vector2(cx - 150.0, top + 40.0), "SCORE", HORIZONTAL_ALIGNMENT_CENTER, 300.0, 11, COL_DIM)
		if rings.combo > 1:
			var ps := 18 + int(_combo_pulse * 10.0)
			c.draw_string(_font, Vector2(cx + 70.0, top + 28.0), "x%d" % rings.combo, HORIZONTAL_ALIGNMENT_LEFT, -1, ps, COL_GOLD)
		_draw_ring_pointer(c, Vector2(cx, cy), size)

	# Speed + boost (bottom left; bottom centre on phones).
	var bl_y := size.y - (110.0 if mobile else 48.0)
	var bl_x := 18.0 if not mobile else size.x * 0.5 - 90.0
	c.draw_string(_font, Vector2(bl_x, bl_y), "%d" % int(round(tm.airspeed * 3.6)), HORIZONTAL_ALIGNMENT_LEFT, -1, 34, COL)
	c.draw_string(_font, Vector2(bl_x + 78.0, bl_y), "km/h", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_DIM)
	var bw := 150.0
	c.draw_rect(Rect2(bl_x, bl_y + 8.0, bw, 7.0), COL_PANEL)
	var e: float = tm.boost_energy
	c.draw_rect(Rect2(bl_x, bl_y + 8.0, bw * e, 7.0), Color(1.0, 0.6, 0.2) if tm.boost > 0.1 else Color(0.5, 0.9, 1.0))
	c.draw_string(_font, Vector2(bl_x, bl_y + 27.0), "BOOST  hold Shift" if not mobile else "BOOST", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_DIM)

	c.draw_arc(Vector2(cx, cy), 5.0, 0.0, TAU, 16, COL_DIM, 1.5)

	if not is_nan(tm.agl) and tm.agl < 70.0 and tm.vs < -10.0:
		var a := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.015)
		c.draw_string(_font, Vector2(cx - 100.0, cy + 90.0), "PULL UP", HORIZONTAL_ALIGNMENT_CENTER, 200.0, 26, Color(COL_RED, a))

	for p in _pops:
		var k: float = p.t / 1.4
		var col: Color = p.col
		col.a = 1.0 - k * k
		var sz: int = (34 if p.big else 22)
		var pos := Vector2(cx - 200.0, cy - 60.0 - k * 70.0)
		c.draw_string(_font, pos, p.text, HORIZONTAL_ALIGNMENT_CENTER, 400.0, sz, col)

	c.draw_string(_font, Vector2(16.0, 26.0), place_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COL_DIM)
	if radio != null and radio.playing:
		c.draw_string(_font, Vector2(16.0, 44.0), "♪ Nightride FM", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_DIM)
	if hint != "":
		var hw: float = min(640.0, size.x - 32.0)
		var lines := _font.get_multiline_string_size(hint, HORIZONTAL_ALIGNMENT_CENTER, hw - 16.0, 13).y
		var hy: float = size.y - (170.0 if mobile else 90.0)
		c.draw_rect(Rect2(cx - hw * 0.5, hy - lines, hw, lines + 12.0), COL_PANEL)
		c.draw_multiline_string(_font, Vector2(cx - hw * 0.5 + 8.0, hy + 12.0 - lines + 13.0), hint, HORIZONTAL_ALIGNMENT_CENTER, hw - 16.0, 13, -1, COL)
	if tiles != null:
		var attr := tiles.attribution()
		if attr != "":
			c.draw_string(_font, Vector2(size.x - 16.0 - 420.0, size.y - 8.0), attr, HORIZONTAL_ALIGNMENT_RIGHT, 420.0, 10, Color(1, 1, 1, 0.6))


func _draw_speed_lines(c: Control, centre: Vector2, size: Vector2, amount: float) -> void:
	var n := 28
	var t := Time.get_ticks_msec() * 0.001
	var rmax: float = max(size.x, size.y) * 0.75
	for i in range(n):
		var a: float = float(i) / n * TAU + sin(t * 3.0 + i) * 0.05
		var r0: float = rmax * (0.35 + 0.25 * fmod(float(i) * 0.37 + t * 2.2, 1.0))
		var r1: float = r0 + rmax * 0.18 * amount
		var d := Vector2(cos(a), sin(a))
		c.draw_line(centre + d * r0, centre + d * r1, Color(1, 1, 1, 0.22 * amount), 2.0)


func _draw_ring_pointer(c: Control, centre: Vector2, size: Vector2) -> void:
	if camera == null or rings.rings.is_empty() or not rings.active:
		return
	var target: Vector3 = rings.next_ring_position()
	var dist: float = aircraft.position.distance_to(target)
	if not camera.is_position_behind(target):
		var sp := camera.unproject_position(target)
		if sp.x > 0.0 and sp.x < size.x and sp.y > 0.0 and sp.y < size.y:
			c.draw_string(_font, sp + Vector2(-50.0, 70.0), "%d m" % int(dist), HORIZONTAL_ALIGNMENT_CENTER, 100.0, 13, COL_GOLD)
			return
	var local: Vector3 = camera.global_transform.affine_inverse() * target
	var dir := Vector2(local.x, -local.y)
	if dir.length() < 1e-3:
		dir = Vector2(0.0, -1.0)
	dir = dir.normalized()
	var p: Vector2 = centre + dir * min(size.x, size.y) * 0.36
	var tip := p + dir * 18.0
	var side := Vector2(-dir.y, dir.x) * 10.0
	c.draw_colored_polygon(PackedVector2Array([tip, p + side, p - side]), COL_GOLD)
	c.draw_string(_font, p - dir * 14.0 + Vector2(-40.0, 5.0), "%d m" % int(dist), HORIZONTAL_ALIGNMENT_CENTER, 80.0, 12, COL_GOLD)
