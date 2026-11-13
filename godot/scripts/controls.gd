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

const ACTIONS := {
	"pitch_up": [KEY_S, KEY_DOWN],
	"pitch_down": [KEY_W, KEY_UP],
	"roll_left": [KEY_A, KEY_LEFT],
	"roll_right": [KEY_D, KEY_RIGHT],
	"yaw_left": [KEY_Q],
	"yaw_right": [KEY_E],
	"throttle_up": [KEY_SHIFT],
	"throttle_down": [KEY_CTRL],
	"brake": [KEY_SPACE],
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
	"brake": JOY_BUTTON_A,
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
	p = clamp(p, -1.0, 1.0) * sensitivity
	r = clamp(r, -1.0, 1.0) * sensitivity
	# Smooth keyboard steps so surfaces travel rather than snap.
	var k := 1.0 - exp(-delta * 25.0)
	pitch = lerp(pitch, p, k)
	roll = lerp(roll, r, k)
	yaw = lerp(yaw, clamp(y, -1.0, 1.0), k)
	throttle_delta = Input.get_action_strength("throttle_up") - Input.get_action_strength("throttle_down") + _touch_throttle
	brake = Input.is_action_pressed("brake")


func set_touch(axes: Vector2, throttle: float) -> void:
	_touch_axes = axes
	_touch_throttle = throttle
	touch_active = true
