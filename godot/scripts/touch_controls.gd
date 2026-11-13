extends CanvasLayer
class_name TouchControls
## On-screen controls for phones/tablets: a virtual stick on the left half,
## a throttle/boost slider on the right, and a row of action buttons.
## Shown only when a touchscreen is present (or ?touch=1).

var enabled := false
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _stick_id := -1
var _throttle_id := -1
var _throttle_value := 0.0     # -1..1 (brake .. boost)
var _draw: Control
var _buttons: Array = []       # [{rect, label, action}]
var _font: Font
var main: Node

const STICK_RADIUS := 70.0
const COL := Color(0.72, 1.0, 0.82, 0.55)
const COL_STRONG := Color(0.72, 1.0, 0.82, 0.9)


func _ready() -> void:
	layer = 6
	_font = ThemeDB.fallback_font
	_draw = Control.new()
	_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_on_draw)
	add_child(_draw)
	visible = false


func set_enabled(on: bool) -> void:
	enabled = on
	visible = on
	if not on:
		Controls.touch_active = false


func _layout() -> void:
	var size := _draw.size
	var s := _scale()
	_buttons.clear()
	var bw := 64.0 * s
	var bh := 44.0 * s
	var gap := 8.0 * s
	var labels := [["LEVEL", "level"], ["LOOP", "loop"], ["ROLL", "barrel_roll"], ["CAM", "camera"], ["MENU", "menu"]]
	var total := labels.size() * bw + (labels.size() - 1) * gap
	var x := size.x * 0.5 - total * 0.5
	var y := size.y - bh - 12.0 * s
	for l in labels:
		_buttons.append({"rect": Rect2(x, y, bw, bh), "label": l[0], "action": l[1]})
		x += bw + gap


func _scale() -> float:
	return clamp(_draw.size.y / 540.0, 0.8, 1.8)


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	var size := _draw.size
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_layout()
			for b in _buttons:
				if b.rect.has_point(e.position):
					_press(b.action)
					get_viewport().set_input_as_handled()
					return
			if e.position.x < size.x * 0.5 and _stick_id < 0:
				_stick_id = e.index
				_stick_origin = e.position
				_stick_pos = e.position
			elif e.position.x >= size.x * 0.5 and _throttle_id < 0:
				_throttle_id = e.index
				_throttle_from(e.position)
			get_viewport().set_input_as_handled()
		else:
			if e.index == _stick_id:
				_stick_id = -1
				_stick_pos = _stick_origin
			if e.index == _throttle_id:
				_throttle_id = -1
				_throttle_value = 0.0
			_push()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_id:
			_stick_pos = d.position
			_push()
			get_viewport().set_input_as_handled()
		elif d.index == _throttle_id:
			_throttle_from(d.position)
			get_viewport().set_input_as_handled()


func _throttle_from(p: Vector2) -> void:
	var size := _draw.size
	var centre := size.y * 0.55
	_throttle_value = clamp((centre - p.y) / (size.y * 0.25), -1.0, 1.0)
	_push()


func _push() -> void:
	var v := (_stick_pos - _stick_origin) / (STICK_RADIUS * _scale())
	if v.length() > 1.0:
		v = v.normalized()
	# Right = roll right, up (negative y) = nose down like a real stick? No:
	# arcade players expect "drag up = go up", so invert.
	Controls.set_touch(Vector2(v.x, -v.y), _throttle_value)
	Controls.brake = _throttle_value < -0.5


func _press(action: String) -> void:
	if main == null:
		return
	match action:
		"level": main.aircraft.level_out()
		"loop": main.aircraft.start_maneuver("loop")
		"barrel_roll": main.aircraft.start_maneuver("roll")
		"camera": main.camera.cycle_mode()
		"menu":
			if main.state == main.State.FLYING:
				main.pause()
			elif main.state == main.State.PAUSED:
				main.resume()


func _process(_delta: float) -> void:
	if enabled:
		_draw.queue_redraw()


func _on_draw() -> void:
	var size := _draw.size
	var s := _scale()
	_layout()
	# Stick.
	var origin := _stick_origin if _stick_id >= 0 else Vector2(110.0 * s, size.y - 120.0 * s)
	var pos := _stick_pos if _stick_id >= 0 else origin
	_draw.draw_arc(origin, STICK_RADIUS * s, 0.0, TAU, 40, COL, 2.0)
	var knob: Vector2 = origin + (pos - origin).limit_length(STICK_RADIUS * s)
	_draw.draw_circle(knob, 22.0 * s, COL_STRONG)
	# Throttle slider.
	var sx := size.x - 60.0 * s
	var cy := size.y * 0.55
	var h := size.y * 0.25
	_draw.draw_line(Vector2(sx, cy - h), Vector2(sx, cy + h), COL, 3.0)
	_draw.draw_string(_font, Vector2(sx - 30.0 * s, cy - h - 8.0), "BOOST", HORIZONTAL_ALIGNMENT_CENTER, 60.0 * s, int(11 * s), COL)
	_draw.draw_string(_font, Vector2(sx - 30.0 * s, cy + h + 16.0 * s), "BRAKE", HORIZONTAL_ALIGNMENT_CENTER, 60.0 * s, int(11 * s), COL)
	_draw.draw_circle(Vector2(sx, cy - _throttle_value * h), 18.0 * s, COL_STRONG)
	# Buttons.
	for b in _buttons:
		_draw.draw_rect(b.rect, Color(0.02, 0.05, 0.04, 0.5))
		_draw.draw_rect(b.rect, COL, false, 1.0)
		_draw.draw_string(_font, Vector2(b.rect.position.x, b.rect.position.y + b.rect.size.y * 0.65), b.label, HORIZONTAL_ALIGNMENT_CENTER, b.rect.size.x, int(13 * s), COL_STRONG)
