extends CanvasLayer
class_name TouchControls
## Phone controls that stay out of the scenery: drag anywhere on the left
## two thirds to steer (no stick graphics, just a faint dot under your
## finger), FIRE and BOOST buttons in the bottom-right corner, tiny LOOP /
## ROLL / MENU buttons.

var enabled := false
var main: Node
var _steer_id := -1
var _steer_origin := Vector2.ZERO
var _steer_pos := Vector2.ZERO
var _held: Dictionary = {}        # touch index -> button action
var _buttons: Array = []
var _draw: Control
var _font: Font

const COL := Color(1.0, 1.0, 1.0, 0.45)
const COL_STRONG := Color(1.0, 1.0, 1.0, 0.85)


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
		Controls.set_touch_fire(false)


func _scale() -> float:
	return clamp(_draw.size.y / 540.0, 0.8, 1.8)


func _layout() -> void:
	var size := _draw.size
	var s := _scale()
	_buttons.clear()
	var big := 78.0 * s
	var m := 14.0 * s
	# Fire: bottom-right. Boost: above it.
	_buttons.append({"rect": Rect2(size.x - big - m, size.y - big - m, big, big), "label": "FIRE", "action": "fire", "round": true})
	_buttons.append({"rect": Rect2(size.x - big - m, size.y - big * 2.0 - m * 2.0, big, big * 0.8), "label": "BOOST", "action": "boost", "round": true})
	_buttons.append({"rect": Rect2(size.x - big * 2.0 - m * 2.0, size.y - big * 0.9 - m, big * 0.8, big * 0.8), "label": "ROCKET", "action": "rocket", "round": true})
	# Arrow pad: bottom-left, translucent (drag-steering anywhere still works).
	var a := 52.0 * s
	var px := m + a
	var py := size.y - m - a * 2.0
	_buttons.append({"rect": Rect2(px, py - a, a, a), "label": "▲", "action": "up", "round": false})
	_buttons.append({"rect": Rect2(px, py + a, a, a), "label": "▼", "action": "down", "round": false})
	_buttons.append({"rect": Rect2(px - a, py, a, a), "label": "◀", "action": "left", "round": false})
	_buttons.append({"rect": Rect2(px + a, py, a, a), "label": "▶", "action": "right", "round": false})
	# Tricks + lock: small, above the fire buttons.
	var sm := 50.0 * s
	var big2 := 78.0 * s
	var col_x := size.x - big2 - m
	var y0 := size.y - big2 * 2.0 - m * 3.0 - sm
	_buttons.append({"rect": Rect2(col_x, y0, sm, sm * 0.7), "label": "LOOP", "action": "loop", "round": false})
	_buttons.append({"rect": Rect2(col_x - sm - m, y0, sm, sm * 0.7), "label": "ROLL", "action": "barrel_roll", "round": false})
	_buttons.append({"rect": Rect2(col_x - (sm + m) * 2.0, y0, sm, sm * 0.7), "label": "LOCK", "action": "lock", "round": false})
	# Menu: top-right, tiny.
	_buttons.append({"rect": Rect2(size.x - 48.0 * s - m, m, 48.0 * s, 30.0 * s), "label": "II", "action": "menu", "round": false})


func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_layout()
			for b in _buttons:
				if b.rect.grow(6.0).has_point(e.position):
					_held[e.index] = b.action
					_press(b.action, true)
					get_viewport().set_input_as_handled()
					return
			if _steer_id < 0:
				_steer_id = e.index
				_steer_origin = e.position
				_steer_pos = e.position
				get_viewport().set_input_as_handled()
		else:
			if _held.has(e.index):
				_press(_held[e.index], false)
				_held.erase(e.index)
			if e.index == _steer_id:
				_steer_id = -1
				Controls.set_touch(Vector2.ZERO, Controls._touch_throttle)
				_push_pad()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _steer_id:
			_steer_pos = d.position
			var v := (_steer_pos - _steer_origin) / (95.0 * _scale())
			if v.length() > 1.0:
				v = v.normalized()
			Controls.set_touch(Vector2(v.x, -v.y), Controls._touch_throttle)
			get_viewport().set_input_as_handled()


func _press(action: String, down: bool) -> void:
	if main == null:
		return
	match action:
		"fire": Controls.set_touch_fire(down)
		"boost":
			Controls.touch_active = true
			Controls._touch_throttle = 1.0 if down else 0.0
		"up", "down", "left", "right":
			_pad[action] = down
			_push_pad()
		"lock":
			if down: main.cycle_target()
		"rocket":
			if down: main.fire_rocket()
		"loop":
			if down: main.aircraft.start_maneuver("loop")
		"barrel_roll":
			if down: main.aircraft.start_maneuver("roll")
		"menu":
			if down:
				if main.state == main.State.RUN:
					main.pause()
				elif main.state == main.State.PAUSED:
					main.resume()


var _pad: Dictionary = {}


func _push_pad() -> void:
	var v := Vector2(0.0, 0.0)
	if _pad.get("left", false): v.x -= 1.0
	if _pad.get("right", false): v.x += 1.0
	if _pad.get("up", false): v.y += 1.0      # up = nose up
	if _pad.get("down", false): v.y -= 1.0
	if _steer_id < 0:
		Controls.set_touch(v, Controls._touch_throttle)


func _process(_delta: float) -> void:
	if enabled:
		_draw.queue_redraw()


func _on_draw() -> void:
	var s := _scale()
	_layout()
	if _steer_id >= 0:
		_draw.draw_circle(_steer_origin, 6.0 * s, COL)
		_draw.draw_circle(_steer_pos, 14.0 * s, COL_STRONG)
	for b in _buttons:
		var r: Rect2 = b.rect
		var active: bool = _held.values().has(b.action)
		var fill := Color(1, 1, 1, 0.22 if active else (0.05 if b.label.length() == 1 else 0.08))
		if b.round:
			var centre: Vector2 = r.get_center()
			var rad: float = min(r.size.x, r.size.y) * 0.5
			_draw.draw_circle(centre, rad, fill)
			_draw.draw_arc(centre, rad, 0.0, TAU, 40, COL, 2.0)
			_draw.draw_string(_font, Vector2(r.position.x, centre.y + 5.0 * s), b.label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(13 * s), COL_STRONG)
		else:
			_draw.draw_rect(r, fill)
			_draw.draw_rect(r, COL, false, 1.0)
			if b.label.length() == 1 and b.action in ["up", "down", "left", "right"]:
				# Arrow pad: draw triangles (the fallback font has no arrow glyphs).
				var cc: Vector2 = r.get_center()
				var h: float = r.size.x * 0.22
				var tri := PackedVector2Array()
				match b.action:
					"up": tri = PackedVector2Array([cc + Vector2(0, -h), cc + Vector2(-h, h * 0.7), cc + Vector2(h, h * 0.7)])
					"down": tri = PackedVector2Array([cc + Vector2(0, h), cc + Vector2(-h, -h * 0.7), cc + Vector2(h, -h * 0.7)])
					"left": tri = PackedVector2Array([cc + Vector2(-h, 0), cc + Vector2(h * 0.7, -h), cc + Vector2(h * 0.7, h)])
					"right": tri = PackedVector2Array([cc + Vector2(h, 0), cc + Vector2(-h * 0.7, -h), cc + Vector2(-h * 0.7, h)])
				_draw.draw_colored_polygon(tri, COL_STRONG)
			else:
				_draw.draw_string(_font, Vector2(r.position.x, r.position.y + r.size.y * 0.65), b.label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(12 * s), COL_STRONG)
