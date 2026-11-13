class_name Vehicles
## Aircraft specifications. Units are SI; coefficients are per radian.
##
## Axis conventions (Godot body frame): forward = -Z, right = +X, up = +Y.
## See aircraft.gd for how each coefficient is used.

const SPECS := {
	"aerion": {
		"name": "Aerion",
		"blurb": "Twin-engine executive jet. Smooth, stable, fast.",
		"model": "res://assets/aerion.glb",
		"model_scale": 1.0,
		"mass": 6200.0,
		"wing_area": 28.0,
		"chord": 2.6,
		"span": 15.0,
		"inertia": Vector3(42000.0, 60000.0, 22000.0),   # pitch, yaw, roll
		"cl0": 0.15, "cla": 5.4, "cl_max_alpha": 15.0,
		"cd0": 0.032, "k_induced": 0.045, "brake_drag": 0.08,
		"cm0": 0.0, "cma": -0.9, "cmq": -14.0, "cmde": 0.55,
		"cnb": 0.09, "cnr": -0.16, "cndr": 0.08, "cnda": 0.012,
		"clb": 0.06, "clp": -0.45, "clda": 0.10, "cyb": -0.6,
		"thrust": 22000.0, "spool": 2.2, "g_limit": 4.5, "stunt_g": 9.0,
		"max_rates": Vector3(35.0, 25.0, 110.0),            # deg/s: pitch, yaw, roll
		"rcs": 0.0,
		"cockpit": Vector3(0.0, 1.25, -5.4),
		"chase": Vector3(0.0, 4.5, 20.0),
		"radius": 7.0,
		"spawn_speed": 130.0,
		"surfaces": {"AileronL": [1, 25.0, -1.0], "AileronR": [1, 25.0, 1.0], "Elevator": [0, 20.0, 1.0], "Rudder": [2, 25.0, 1.0]},
		"engine": "jet",
	},
	"cyberwing": {
		"name": "Cyberwing",
		"blurb": "Neon strike fighter. Afterburner, vicious roll rate.",
		"model": "res://assets/cyberwing.glb",
		"model_scale": 1.0,
		"mass": 9500.0,
		"wing_area": 34.0,
		"chord": 3.6,
		"span": 11.5,
		"inertia": Vector3(55000.0, 70000.0, 14000.0),
		"cl0": 0.08, "cla": 4.6, "cl_max_alpha": 24.0,
		"cd0": 0.031, "k_induced": 0.075, "brake_drag": 0.12,
		"cm0": 0.0, "cma": -0.5, "cmq": -9.0, "cmde": 0.75,
		"cnb": 0.11, "cnr": -0.2, "cndr": 0.1, "cnda": 0.005,
		"clb": 0.03, "clp": -0.3, "clda": 0.16, "cyb": -0.8,
		"thrust": 70000.0, "spool": 1.2, "g_limit": 9.0, "stunt_g": 12.0,
		"max_rates": Vector3(60.0, 35.0, 260.0),
		"rcs": 0.0,
		"cockpit": Vector3(0.0, 1.1, -4.2),
		"chase": Vector3(0.0, 4.0, 19.0),
		"radius": 7.0,
		"spawn_speed": 180.0,
		"surfaces": {"AileronL": [1, 25.0, -1.0], "AileronR": [1, 25.0, 1.0], "Elevator": [0, 20.0, 1.0], "Rudder": [2, 25.0, 1.0]},
		"engine": "afterburner",
	},
	"wayfarer": {
		"name": "Wayfarer",
		"blurb": "Atmospheric scout ship. Vectored thrust, no stall, drifts like a dream.",
		"model": "res://assets/wayfarer.glb",
		"model_scale": 1.0,
		"mass": 4200.0,
		"wing_area": 40.0,
		"chord": 6.0,
		"span": 12.0,
		"inertia": Vector3(30000.0, 36000.0, 18000.0),
		"cl0": 0.05, "cla": 2.8, "cl_max_alpha": 40.0,
		"cd0": 0.05, "k_induced": 0.05, "brake_drag": 0.2,
		"cm0": 0.0, "cma": -0.4, "cmq": -10.0, "cmde": 0.4,
		"cnb": 0.08, "cnr": -0.25, "cndr": 0.08, "cnda": 0.0,
		"clb": 0.02, "clp": -0.5, "clda": 0.09, "cyb": -0.9,
		"thrust": 90000.0, "spool": 0.6, "g_limit": 7.0, "stunt_g": 10.0,
		"max_rates": Vector3(50.0, 40.0, 180.0),
		"rcs": 90000.0,                                      # vectored torque, N·m at full stick
		"cockpit": Vector3(0.0, 1.0, -3.0),
		"chase": Vector3(0.0, 4.5, 18.0),
		"radius": 6.0,
		"spawn_speed": 120.0,
		"surfaces": {"ElevonL": [3, 22.0, 1.0], "ElevonR": [4, 22.0, 1.0]},
		"engine": "ion",
	},
}

const ORDER := ["aerion", "cyberwing", "wayfarer"]


static func get_spec(id: String) -> Dictionary:
	return SPECS.get(id, SPECS["aerion"])
