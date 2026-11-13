extends CanvasLayer
class_name Hud
## Flight HUD: artificial horizon ladder, heading tape, speed / altitude
## boxes, throttle + G, warnings, and the data attribution Google requires.

var aircraft: Aircraft
var tiles: GoogleTiles
var camera: FlightCamera
var radio: Radio
var compact := false
var place_name := ""
var hint := ""
var _hint_timer := 0.0
var _toast := ""
var _toast_timer := 0.0
var _draw: Control
var _font: Font
var _mono: Font
var fps_visible := true

const COL_HUD := Color(0.72, 1.0, 0.82, 0.95)
const COL_DIM := Color(0.72, 1.0, 0.82, 0.45)
const COL_WARN := Color(1.0, 0.45, 0.35, 1.0)
const COL_PANEL := Color(0.02, 0.05, 0.04, 0.55)


func _ready() -> void:
	layer = 5
	_draw = Control.new()
	_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_on_draw)
	add_child(_draw)
	_font = ThemeDB.fallback_font
	_mono = _font


func _process(delta: float) -> void:
	if _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			hint = ""
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast = ""
	_draw.queue_redraw()


func show_hint(text: String, seconds: float = 6.0) -> void:
	hint = text
	_hint_timer = seconds


func toast(text: String, seconds: float = 3.0) -> void:
	_toast = text
	_toast_timer = seconds


func _on_draw() -> void:
	if aircraft == null:
		return
	var c := _draw
	var size := c.size
	var tm := aircraft.telemetry()
	var cx := size.x * 0.5
	var cy := size.y * 0.5
	var cockpit := camera != null and camera.mode == FlightCamera.Mode.COCKPIT

	if not compact:
		_draw_horizon(c, Vector2(cx, cy), tm, cockpit)
		_draw_heading_tape(c, Vector2(cx, 34.0), size.x, tm.heading)
	_draw_box(c, Vector2(cx - size.x * 0.22 - 110.0, cy - 30.0), Vector2(110.0, 60.0), "%d" % int(round(tm.airspeed * 3.6)), "km/h", "")
	var alt_label := "m MSL"
	var agl_text := ""
	if not is_nan(tm.agl):
		agl_text = "%d m AGL" % int(tm.agl)
	_draw_box(c, Vector2(cx + size.x * 0.22, cy - 30.0), Vector2(110.0, 60.0), "%d" % int(round(tm.altitude)), alt_label, agl_text)

	# Throttle + G + assist (bottom centre).
	var y := size.y - 58.0
	var tw := 180.0
	var tx := cx - tw * 0.5
	c.draw_rect(Rect2(tx, y, tw, 10.0), COL_DIM, false, 1.0)
	c.draw_rect(Rect2(tx + 1.0, y + 1.0, (tw - 2.0) * tm.throttle, 8.0), COL_HUD)
	c.draw_rect(Rect2(tx + (tw - 2.0) * tm.throttle_cmd, y - 3.0, 2.0, 16.0), COL_HUD)
	var g_col := COL_HUD if abs(tm.g) < float(aircraft.spec.g_limit) else COL_WARN
	c.draw_string(_font, Vector2(tx - 90.0, y + 10.0), "%.1f G" % tm.g, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, g_col)
	c.draw_string(_font, Vector2(tx, y + 30.0), "THR %d%%" % int(round(tm.throttle * 100.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_DIM)
	c.draw_string(_font, Vector2(tx + tw + 12.0, y + 10.0), "%s · %s" % [tm.assist, camera.MODE_NAMES[camera.mode] if camera else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_DIM)
	if tm.maneuver != "":
		c.draw_string(_font, Vector2(cx - 60.0, y - 12.0), {"loop": "LOOP", "roll": "BARREL ROLL", "level": "RECOVERING"}.get(tm.maneuver, ""), HORIZONTAL_ALIGNMENT_CENTER, 120, 15, COL_HUD)

	# Warnings.
	if tm.stall and aircraft.airspeed > 20.0:
		_pulse_text(c, Vector2(cx, cy + 90.0), "STALL", 26)
	elif not is_nan(tm.agl) and tm.agl < 90.0 and tm.vs < -8.0:
		_pulse_text(c, Vector2(cx, cy + 90.0), "PULL UP", 26)

	# Top-left: place, flight stats.
	var top := 14.0
	if place_name != "":
		c.draw_string(_font, Vector2(16.0, top + 18.0), place_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COL_HUD)
		top += 22.0
	c.draw_string(_font, Vector2(16.0, top + 18.0), "%s · %.1f km · %s" % [tm.vehicle, tm.distance / 1000.0, _fmt_time(tm.time)], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_DIM)
	top += 20.0
	if radio != null:
		c.draw_string(_font, Vector2(16.0, top + 18.0), "♪ " + radio.status, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_DIM)
		top += 18.0

	# Top-right: fps + tiles.
	if fps_visible and tiles != null:
		var st := tiles.stats()
		var s := "%d fps · %d tiles" % [Engine.get_frames_per_second(), st.visible]
		if st.queued + st.inflight > 0:
			s += " · loading %d" % (st.queued + st.inflight)
		c.draw_string(_font, Vector2(size.x - 16.0 - 260.0, 30.0), s, HORIZONTAL_ALIGNMENT_RIGHT, 260, 13, COL_DIM)

	# Hints / toasts.
	if hint != "":
		var hw: float = min(640.0, size.x - 32.0)
		var lines := _font.get_multiline_string_size(hint, HORIZONTAL_ALIGNMENT_CENTER, hw - 16.0, 13).y
		c.draw_rect(Rect2(cx - hw * 0.5, size.y - 108.0 - lines, hw, lines + 12.0), COL_PANEL)
		c.draw_multiline_string(_font, Vector2(cx - hw * 0.5 + 8.0, size.y - 96.0 - lines + 13.0), hint, HORIZONTAL_ALIGNMENT_CENTER, hw - 16.0, 13, -1, COL_HUD)
	if _toast != "":
		c.draw_string(_font, Vector2(cx - 300.0, cy - 140.0), _toast, HORIZONTAL_ALIGNMENT_CENTER, 600, 20, COL_HUD)

	# Attribution (required by the Map Tiles API terms).
	if tiles != null:
		var attr := tiles.attribution()
		if attr != "":
			c.draw_string(_font, Vector2(size.x - 16.0 - 520.0, size.y - 10.0), "Data: " + attr, HORIZONTAL_ALIGNMENT_RIGHT, 520, 11, Color(1, 1, 1, 0.75))


func _fmt_time(t: float) -> String:
	var s := int(t)
	return "%d:%02d" % [s / 60, s % 60]


func _pulse_text(c: Control, pos: Vector2, text: String, px: int) -> void:
	var a := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.012)
	var col := COL_WARN
	col.a = a
	c.draw_string(_font, pos - Vector2(100.0, 0.0), text, HORIZONTAL_ALIGNMENT_CENTER, 200, px, col)


func _draw_box(c: Control, pos: Vector2, sz: Vector2, big: String, unit: String, sub: String) -> void:
	c.draw_rect(Rect2(pos, sz), COL_PANEL)
	c.draw_rect(Rect2(pos, sz), COL_DIM, false, 1.0)
	c.draw_string(_font, pos + Vector2(0.0, 36.0), big, HORIZONTAL_ALIGNMENT_CENTER, sz.x, 28, COL_HUD)
	c.draw_string(_font, pos + Vector2(0.0, 54.0), unit, HORIZONTAL_ALIGNMENT_CENTER, sz.x, 12, COL_DIM)
	if sub != "":
		c.draw_string(_font, pos + Vector2(0.0, sz.y + 16.0), sub, HORIZONTAL_ALIGNMENT_CENTER, sz.x, 12, COL_DIM)


func _draw_heading_tape(c: Control, centre: Vector2, width: float, heading: float) -> void:
	var half: float = min(width * 0.25, 260.0)
	var px_per_deg: float = half / 45.0
	c.draw_line(centre + Vector2(-half, 12.0), centre + Vector2(half, 12.0), COL_DIM, 1.0)
	for d in range(-50, 51):
		var deg := int(round(heading)) + d
		var x: float = centre.x + (float(deg) - heading) * px_per_deg
		if abs(x - centre.x) > half:
			continue
		var h := posmod(deg, 360)
		if h % 10 == 0:
			c.draw_line(Vector2(x, 12.0 + centre.y), Vector2(x, centre.y + 4.0), COL_DIM, 1.0)
			var label: String = {0: "N", 90: "E", 180: "S", 270: "W"}.get(h, "%d" % (h / 10))
			c.draw_string(_font, Vector2(x - 12.0, centre.y - 2.0), str(label), HORIZONTAL_ALIGNMENT_CENTER, 24, 12, COL_DIM)
		elif h % 5 == 0:
			c.draw_line(Vector2(x, 12.0 + centre.y), Vector2(x, centre.y + 8.0), COL_DIM, 1.0)
	c.draw_colored_polygon(PackedVector2Array([centre + Vector2(0.0, 14.0), centre + Vector2(-5.0, 22.0), centre + Vector2(5.0, 22.0)]), COL_HUD)
	c.draw_string(_font, centre + Vector2(-20.0, 40.0), "%03d" % (int(round(heading)) % 360), HORIZONTAL_ALIGNMENT_CENTER, 40, 14, COL_HUD)


func _draw_horizon(c: Control, centre: Vector2, tm: Dictionary, cockpit: bool) -> void:
	var pitch: float = tm.pitch
	var bank: float = tm.bank
	var px_per_deg := 6.0
	var rot := deg_to_rad(-bank)
	var xf := Transform2D(rot, centre)
	# Pitch ladder: lines every 10 degrees, clipped to a circle.
	var radius := 170.0
	for p in range(-90, 91, 10):
		var dy := (float(p) - pitch) * px_per_deg
		if abs(dy) > radius:
			continue
		var w := 70.0 if p != 0 else 160.0
		var col := COL_HUD if p == 0 else COL_DIM
		var a := xf * Vector2(-w, -dy)
		var b := xf * Vector2(w, -dy)
		if p == 0:
			c.draw_line(a, xf * Vector2(-30.0, -dy), col, 2.0)
			c.draw_line(xf * Vector2(30.0, -dy), b, col, 2.0)
		else:
			c.draw_line(a, xf * Vector2(-18.0, -dy), col, 1.0)
			c.draw_line(xf * Vector2(18.0, -dy), b, col, 1.0)
			c.draw_string(_font, xf * Vector2(w + 6.0, -dy + 5.0), str(abs(p)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	# Aircraft reference symbol.
	c.draw_line(centre + Vector2(-26.0, 0.0), centre + Vector2(-8.0, 0.0), COL_HUD, 2.0)
	c.draw_line(centre + Vector2(8.0, 0.0), centre + Vector2(26.0, 0.0), COL_HUD, 2.0)
	c.draw_line(centre + Vector2(0.0, -8.0), centre + Vector2(0.0, 0.0), COL_HUD, 2.0)
	# Bank arc.
	var arc_r := 150.0
	for d in [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]:
		var ang := deg_to_rad(float(d)) - PI * 0.5
		var r0 := arc_r
		var r1 := arc_r + (10.0 if d % 30 == 0 else 6.0)
		c.draw_line(centre + Vector2(cos(ang), sin(ang)) * r0, centre + Vector2(cos(ang), sin(ang)) * r1, COL_DIM, 1.0)
	var bang := deg_to_rad(-bank) - PI * 0.5
	var bp := centre + Vector2(cos(bang), sin(bang)) * (arc_r - 4.0)
	c.draw_colored_polygon(PackedVector2Array([bp, bp + Vector2(-5.0, 10.0).rotated(deg_to_rad(-bank)), bp + Vector2(5.0, 10.0).rotated(deg_to_rad(-bank))]), COL_HUD)
	# Flight-path marker (where the velocity vector points).
	if aircraft.airspeed > 10.0 and not cockpit:
		var v := aircraft.velocity.normalized()
		var right := aircraft.basis.x
		var up := aircraft.basis.y
		var dx := rad_to_deg(asin(clamp(v.dot(right), -1.0, 1.0)))
		var dyy := rad_to_deg(asin(clamp(v.dot(up), -1.0, 1.0)))
		var fpm := centre + Vector2(dx, -dyy) * px_per_deg
		c.draw_arc(fpm, 7.0, 0.0, TAU, 20, COL_HUD, 1.5)
		c.draw_line(fpm + Vector2(-7.0, 0.0), fpm + Vector2(-14.0, 0.0), COL_HUD, 1.5)
		c.draw_line(fpm + Vector2(7.0, 0.0), fpm + Vector2(14.0, 0.0), COL_HUD, 1.5)
		c.draw_line(fpm + Vector2(0.0, -7.0), fpm + Vector2(0.0, -12.0), COL_HUD, 1.5)
