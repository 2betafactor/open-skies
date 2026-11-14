extends Node
## Controls — defines the input map in code (keyboard + gamepad) and exposes
## smoothed axis values for the flight model.
##
## Keys: W/S pitch · A/D roll · Q/E rudder · Shift/Ctrl throttle · Space brake
## L level · B assist · C camera · R loop · T barrel roll · H hide HUD · Esc menu
## Gamepad: left stick pitch/roll, bumpers rudder, triggers throttle.

var pitch := 0.0      # +1 = nose up
var roll := 0.0       # +1 = roll right
var yaw := 0.0        # +1 = nose right
var throttle_delta := 0.0
var brake := false
var sensitivity := 1.0

var _touch_axes := Vector2.ZERO
var _touch_throttle := 0.0
var touch_active := false
var fire := false
var mouse_aim := false          # desktop: steer toward the mouse cursor
var _mouse_axes := Vector2.ZERO
var _mouse_seen := false
var mouse_fire := false
var assist := Vector2.ZERO      # auto-track nudge (roll, pitch) added when the stick is idle
var hands_off := true

const ACTIONS := {
	"pitch_up": [KEY_S, KEY_DOWN],
	"pitch_down": [KEY_W, KEY_UP],
	"roll_left": [KEY_A, KEY_LEFT],
	"roll_right": [KEY_D, KEY_RIGHT],
	"yaw_left": [KEY_Q],
	"yaw_right": [KEY_E],
	"throttle_up": [KEY_SHIFT],
	"throttle_down": [KEY_CTRL],
	"fire": [KEY_SPACE, KEY_F],
	"lock": [KEY_TAB],
	"rocket": [KEY_E, KEY_CTRL],
	"brake": [KEY_X],
	"level": [KEY_L],
	"assist": [KEY_B],
	"camera": [KEY_C],
	"loop": [KEY_R],
	"barrel_roll": [KEY_T],
	"hud": [KEY_H],
	"menu": [KEY_ESCAPE],
	"radio": [KEY_M],
	"photo": [KEY_P],
}

const PAD_AXES := {
	"pitch_up": [JOY_AXIS_LEFT_Y, 1.0],
	"pitch_down": [JOY_AXIS_LEFT_Y, -1.0],
	"roll_left": [JOY_AXIS_LEFT_X, -1.0],
	"roll_right": [JOY_AXIS_LEFT_X, 1.0],
	"throttle_up": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
	"throttle_down": [JOY_AXIS_TRIGGER_LEFT, 1.0],
}

const PAD_BUTTONS := {
	"yaw_left": JOY_BUTTON_LEFT_SHOULDER,
	"yaw_right": JOY_BUTTON_RIGHT_SHOULDER,
	"level": JOY_BUTTON_Y,
	"camera": JOY_BUTTON_BACK,
	"loop": JOY_BUTTON_X,
	"barrel_roll": JOY_BUTTON_B,
	"fire": JOY_BUTTON_A,
	"lock": JOY_BUTTON_X,
	"rocket": JOY_BUTTON_RIGHT_SHOULDER,
	"brake": JOY_BUTTON_B,
	"menu": JOY_BUTTON_START,
}


func _ready() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for action in PAD_AXES:
		var ev := InputEventJoypadMotion.new()
		ev.axis = PAD_AXES[action][0]
		ev.axis_value = PAD_AXES[action][1]
		InputMap.action_add_event(action, ev)
	for action in PAD_BUTTONS:
		var ev := InputEventJoypadButton.new()
		ev.button_index = PAD_BUTTONS[action]
		InputMap.action_add_event(action, ev)


func _process(delta: float) -> void:
	var p := Input.get_action_strength("pitch_up") - Input.get_action_strength("pitch_down")
	var r := Input.get_action_strength("roll_right") - Input.get_action_strength("roll_left")
	var y := Input.get_action_strength("yaw_right") - Input.get_action_strength("yaw_left")
	if touch_active:
		p += -_touch_axes.y
		r += _touch_axes.x
	if mouse_aim and _mouse_seen and abs(p) < 0.05 and abs(r) < 0.05:
		p = -_mouse_axes.y
		r = _mouse_axes.x
	hands_off = abs(p) < 0.08 and abs(r) < 0.08
	if hands_off:
		p += assist.y
		r += assist.x
	p = clamp(p, -1.0, 1.0) * sensitivity
	r = clamp(r, -1.0, 1.0) * sensitivity
	# Smooth keyboard steps so surfaces travel rather than snap.
	var k := 1.0 - exp(-delta * 25.0)
	pitch = lerp(pitch, p, k)
	roll = lerp(roll, r, k)
	yaw = lerp(yaw, clamp(y, -1.0, 1.0), k)
	throttle_delta = Input.get_action_strength("throttle_up") - Input.get_action_strength("throttle_down") + _touch_throttle
	brake = Input.is_action_pressed("brake")
	fire = Input.is_action_pressed("fire") or mouse_fire or _touch_fire


var _touch_fire := false


func set_touch_fire(on: bool) -> void:
	_touch_fire = on


func _input(event: InputEvent) -> void:
	if not mouse_aim:
		return
	if event is InputEventMouseMotion:
		var vp := get_viewport().get_visible_rect().size
		var centre := vp * 0.5
		var off: Vector2 = (event.position - centre) / (min(vp.x, vp.y) * 0.32)
		var len := off.length()
		var dead := 0.1
		if len < dead:
			off = Vector2.ZERO
		else:
			off = off.normalized() * clamp((len - dead) / (1.0 - dead), 0.0, 1.0)
		_mouse_axes = off
		_mouse_seen = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		mouse_fire = event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		rocket_requested = true

var rocket_requested := false


func set_touch(axes: Vector2, throttle: float) -> void:
	_touch_axes = axes
	_touch_throttle = throttle
	touch_active = true
