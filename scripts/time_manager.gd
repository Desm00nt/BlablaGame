extends Node

## Day/night cycle. One in-game day = `day_length_seconds` of real time
## (5 minutes by default).
##
## CPU cost is deliberately minimal:
##   * `time_of_day` is the only state; it is a single float accumulated per
##     frame. Nothing is allocated in the loop and no nodes are looked up.
##   * The expensive part is not the maths but the fact that changing the sky
##     uniform makes Godot re-render the sky radiance cubemap. So all GPU-facing
##     writes are throttled to `update_rate` Hz. At 30 Hz the sun still moves
##     1.2 deg/s * 1/30 s = 0.04 deg per tick, which is invisible.
##
## The sun direction formula is duplicated in shaders/sky.gdshader
## (sun_direction()) - SUN_TILT must match there.

const SUN_TILT: float = 0.40

@export var day_length_seconds: float = 300.0
@export_range(0.0, 1.0) var start_time_of_day: float = 0.30
@export var update_rate: float = 30.0
@export var min_ambient_energy: float = 0.35
@export var max_ambient_energy: float = 1.0
@export var sun_energy_night: float = 0.03
@export var sun_energy_day: float = 1.25

## 0.0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset.
var time_of_day: float = 0.30

var _accum: float = 0.0
var _sun: DirectionalLight3D
var _env: Environment
var _sky_mat: ShaderMaterial

signal time_changed(new_time_of_day: float)


func _ready() -> void:
	time_of_day = start_time_of_day
	var root := get_parent()
	_sun = root.get_node_or_null(^"DirectionalLight3D") as DirectionalLight3D
	var world_env := root.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if world_env != null:
		_env = world_env.environment
	if _env != null and _env.sky != null:
		_sky_mat = _env.sky.sky_material as ShaderMaterial
	if _sun == null:
		push_warning("[TimeManager] no DirectionalLight3D sibling found")
	if _sky_mat == null:
		push_warning("[TimeManager] no ShaderMaterial sky found - sky will stay static")
	_apply()


func _process(delta: float) -> void:
	time_of_day = fposmod(time_of_day + delta / maxf(day_length_seconds, 0.001), 1.0)
	_accum += delta
	if _accum < 1.0 / maxf(update_rate, 1.0):
		return
	_accum = 0.0
	_apply()
	time_changed.emit(time_of_day)


## 1.0 in full daylight, 0.0 at night.
func daylight_factor() -> float:
	return clampf(sin((time_of_day - 0.25) * TAU) * 2.6 + 0.24, 0.0, 1.0)


func sun_direction() -> Vector3:
	return TerrainNoise.sun_direction(time_of_day, SUN_TILT)


func _apply() -> void:
	var to_sun := sun_direction()
	var elev := to_sun.y
	var day := daylight_factor()
	# Peaks while the sun sits on the horizon.
	var dusk := 1.0 - clampf(absf(elev) * 4.5, 0.0, 1.0)

	if _sun != null:
		_sun.global_transform = Transform3D(_basis_for_sun(to_sun), _sun.global_position)
		_sun.light_energy = lerpf(sun_energy_night, sun_energy_day, day)
		# Warm the light near the horizon, cool it slightly at night.
		var c := Color(1.0, 0.96, 0.90).lerp(Color(1.0, 0.52, 0.30), dusk * 0.85)
		_sun.light_color = c.lerp(Color(0.55, 0.65, 0.90), (1.0 - day) * 0.5)

	if _sky_mat != null:
		_sky_mat.set_shader_parameter("time_of_day", time_of_day)

	if _env != null:
		# ambient_light_source is SKY in main.tscn, so the sky itself provides the
		# colour; only the energy needs driving.
		_env.ambient_light_energy = lerpf(min_ambient_energy, max_ambient_energy, day)
		var fog := Color(0.70, 0.78, 0.88).lerp(Color(0.85, 0.52, 0.36), dusk * 0.7)
		_env.fog_light_color = fog.lerp(Color(0.09, 0.11, 0.18), (1.0 - day) * 0.75)


## Builds a basis whose -Z (the direction a DirectionalLight3D shines) points
## away from the sun. Constructed by hand instead of with look_at_from() so the
## degenerate case at solar noon, where the sun is straight up and the up hint
## is parallel to the view axis, cannot produce a NaN basis.
func _basis_for_sun(to_sun: Vector3) -> Basis:
	var z := to_sun.normalized()
	var up := Vector3(0.0, 0.0, 1.0) if absf(z.y) > 0.98 else Vector3.UP
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	return Basis(x, y, z)
