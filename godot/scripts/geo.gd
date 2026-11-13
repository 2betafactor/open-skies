extends Node
## Geo — WGS84 geodesy in double precision plus a floating local frame.
##
## GDScript floats are 64-bit, so all Earth-centred (ECEF) math is done on
## plain Arrays of three floats. Vector3 is 32-bit, so only *local* coordinates
## (relative to the current origin) are ever stored in Vector3.
##
## Local frame (Godot conventions): +X = east, +Y = up, -Z = north.
## Everything in the scene — tiles, aircraft, camera — lives in this frame.
## When the aircraft strays far from the origin the frame is rebased so the
## 32-bit coordinates stay precise (see `set_origin` and `origin_epoch`).

const A := 6378137.0
const F := 1.0 / 298.257223563
const E2 := F * (2.0 - F)
const B := A * (1.0 - F)

var origin_lat := 0.0
var origin_lon := 0.0
var origin_h := 0.0
var origin_ecef := [0.0, 0.0, 0.0]
## Rows of the ECEF -> local rotation: east, up, south (= -north).
var _r := [[1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, -1.0, 0.0]]
## Increments whenever the origin moves; consumers cache per epoch.
var origin_epoch := 0

signal origin_changed


func geodetic_to_ecef(lat_deg: float, lon_deg: float, h: float) -> Array:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	var sl := sin(lat)
	var cl := cos(lat)
	var n := A / sqrt(1.0 - E2 * sl * sl)
	return [(n + h) * cl * cos(lon), (n + h) * cl * sin(lon), (n * (1.0 - E2) + h) * sl]


func ecef_to_geodetic(x: float, y: float, z: float) -> Array:
	# Bowring / iterative closed form; accurate to mm for all altitudes we fly.
	var lon := atan2(y, x)
	var p := sqrt(x * x + y * y)
	var lat := atan2(z, p * (1.0 - E2))
	var h := 0.0
	for _i in range(6):
		var sl := sin(lat)
		var n := A / sqrt(1.0 - E2 * sl * sl)
		h = p / cos(lat) - n
		lat = atan2(z, p * (1.0 - E2 * n / (n + h)))
	return [rad_to_deg(lat), rad_to_deg(lon), h]


## East / north / up unit vectors (ECEF) at a geodetic position.
func enu_axes(lat_deg: float, lon_deg: float) -> Array:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	var sl := sin(lat)
	var cl := cos(lat)
	var so := sin(lon)
	var co := cos(lon)
	var east := [-so, co, 0.0]
	var north := [-sl * co, -sl * so, cl]
	var up := [cl * co, cl * so, sl]
	return [east, north, up]


func set_origin(lat_deg: float, lon_deg: float, h: float = 0.0) -> void:
	origin_lat = lat_deg
	origin_lon = lon_deg
	origin_h = h
	origin_ecef = geodetic_to_ecef(lat_deg, lon_deg, h)
	var axes := enu_axes(lat_deg, lon_deg)
	var north: Array = axes[1]
	_r = [axes[0], axes[2], [-north[0], -north[1], -north[2]]]
	origin_epoch += 1
	origin_changed.emit()


func ecef_to_local(x: float, y: float, z: float) -> Vector3:
	var dx: float = x - origin_ecef[0]
	var dy: float = y - origin_ecef[1]
	var dz: float = z - origin_ecef[2]
	return Vector3(
		_r[0][0] * dx + _r[0][1] * dy + _r[0][2] * dz,
		_r[1][0] * dx + _r[1][1] * dy + _r[1][2] * dz,
		_r[2][0] * dx + _r[2][1] * dy + _r[2][2] * dz)


func ecef_arr_to_local(e: Array) -> Vector3:
	return ecef_to_local(e[0], e[1], e[2])


func local_to_ecef(v: Vector3) -> Array:
	# Transpose of _r (orthonormal) applied to v, plus origin.
	var lx := float(v.x)
	var ly := float(v.y)
	var lz := float(v.z)
	return [
		origin_ecef[0] + _r[0][0] * lx + _r[1][0] * ly + _r[2][0] * lz,
		origin_ecef[1] + _r[0][1] * lx + _r[1][1] * ly + _r[2][1] * lz,
		origin_ecef[2] + _r[0][2] * lx + _r[1][2] * ly + _r[2][2] * lz]


## Rotate an ECEF direction (no translation) into the local frame.
func ecef_dir_to_local(x: float, y: float, z: float) -> Vector3:
	return Vector3(
		_r[0][0] * x + _r[0][1] * y + _r[0][2] * z,
		_r[1][0] * x + _r[1][1] * y + _r[1][2] * z,
		_r[2][0] * x + _r[2][1] * y + _r[2][2] * z)


## The ECEF->local rotation as a float Basis (rotation only, well conditioned).
func ecef_basis() -> Basis:
	var e: Vector3 = Vector3(_r[0][0], _r[0][1], _r[0][2])
	var u: Vector3 = Vector3(_r[1][0], _r[1][1], _r[1][2])
	var s: Vector3 = Vector3(_r[2][0], _r[2][1], _r[2][2])
	# Basis rows are the local axes expressed in ECEF; Godot's Basis is column
	# based so build it from rows (x, y, z) explicitly.
	var b := Basis()
	b.x = Vector3(e.x, u.x, s.x)
	b.y = Vector3(e.y, u.y, s.y)
	b.z = Vector3(e.z, u.z, s.z)
	return b


func local_to_geodetic(v: Vector3) -> Array:
	var e: Array = local_to_ecef(v)
	return ecef_to_geodetic(e[0], e[1], e[2])


func geodetic_to_local(lat_deg: float, lon_deg: float, h: float) -> Vector3:
	return ecef_arr_to_local(geodetic_to_ecef(lat_deg, lon_deg, h))


## Great-circle distance in metres between two geodetic points.
func distance_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var p1 := deg_to_rad(lat1)
	var p2 := deg_to_rad(lat2)
	var dl := deg_to_rad(lon2 - lon1)
	var h := pow(sin((p2 - p1) * 0.5), 2) + cos(p1) * cos(p2) * pow(sin(dl * 0.5), 2)
	return 2.0 * 6371008.8 * atan2(sqrt(h), sqrt(max(0.0, 1.0 - h)))
