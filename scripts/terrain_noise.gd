class_name TerrainNoise
extends RefCounted

## CPU mirror of the noise + height field used by shaders/terrain.gdshader and
## shaders/water.gdshader.
##
## This exists so the world generator can place trees/grass/rocks and build the
## terrain collision at exactly the heights the GPU displaces the mesh to.
##
## The integer hash (rather than the usual float hash) is deliberate: it is the
## only form that a GDScript int64 and a GLSL uint32 evaluate identically, as
## long as every intermediate product is masked back to 32 bits. Keep the
## constants below in sync with the two shaders.
##
## Verified against the GLSL by tests/check_noise_parity.py.

const NOISE_OFFSET: int = 8192
const TERRAIN_FREQ: float = 0.016
const TERRAIN_OCTAVES: int = 4

## World is 400 x 400 m (4x the original 200 x 200 area). Every system that
## hardcodes the old extent (scatter range, chunk bucketing, prop counts)
## derives from WORLD_HALF instead.
const WORLD_HALF: float = 200.0

## Measured output range of fbm(): over 200x200 it was [0.099, 0.699]; over
## the full 400x400 world it is [0.088, 0.817]. The constants below are kept
## at the original 200x200 values on purpose: clamping swallows only ~0.04%
## of terrain below zero and ~2.5% of the highest peaks into the plateau,
## which is invisible in practice, and keeping them preserves the exact
## height field the first three landmarks were placed against.
const NOISE_MIN: float = 0.10
const NOISE_INV_RANGE: float = 1.0 / 0.60

const SPAWN_HEIGHT: float = 1.0
const LAKE_CENTER: Vector2 = Vector2(42.0, -30.0)
const LAKE_DEPTH: float = -6.5

## Construction pads: the ground under each landmark is flattened to a fixed
## target height so buildings always sit flush with the terrain (structures
## used to float or sink on slopes). Entries: [center, radius, target_height].
## The targets are the measured raw fbm heights at the centres (probe script),
## hardcoded because the GLSL mirrors need constants too.
const PADS: Array = [
	[Vector2(3.0, -2.5), 10.0, 1.0],        # camp: equals SPAWN_HEIGHT
	[Vector2(36.0, 58.0), 18.0, 8.3],       # village Kamenny Brod
	[Vector2(-72.0, 78.0), 15.0, 14.8],     # barrow Ash-Veil
	[Vector2(-40.0, -72.0), 24.0, 11.3],    # dungeon courtyard
]

## The dungeon pad carries a sunken courtyard: inside the bowl radius the
## ground carves down to PIT_FLOOR, between bowl radii it ramps back up to the
## pad level (walkable slope, no stairs needed).
const DUNGEON_INDEX: int = 3
const PIT_INNER: float = 9.0
const PIT_OUTER: float = 18.0
const PIT_DEPTH: float = 4.8
const PIT_FLOOR: float = 11.3 - 4.8  # 6.5, comfortably above the water line

## Height of the water plane in main.tscn (Water node is translated to this y).
const WATER_LEVEL: float = -1.5

## Altitude bands. Kept in sync with the uniform defaults of terrain.gdshader
## so props are never placed on a surface the shader paints as bare rock/snow.
const GRASS_LINE: float = 8.0
const ROCK_LINE: float = 13.0
const SNOW_LINE: float = 16.0


static func hash2f(cx: int, cy: int) -> float:
	# Every step is masked to 32 bits so the int64 arithmetic matches the
	# wrapping uint32 arithmetic of the shader exactly.
	var h: int = (cx * 374761393 + cy * 668265263 + 1013904223) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	return float(h & 0x7FFFFF) * (1.0 / 8388608.0)


static func value_noise(p: Vector2) -> float:
	var i: Vector2 = p.floor()
	var f: Vector2 = p - i
	var u: Vector2 = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var ix: int = int(i.x) + NOISE_OFFSET
	var iy: int = int(i.y) + NOISE_OFFSET
	var a: float = hash2f(ix, iy)
	var b: float = hash2f(ix + 1, iy)
	var c: float = hash2f(ix, iy + 1)
	var d: float = hash2f(ix + 1, iy + 1)
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)


static func fbm(p: Vector2) -> float:
	var sum: float = 0.0
	var amp: float = 0.5
	var freq: float = 1.0
	for _i in TERRAIN_OCTAVES:
		sum += amp * value_noise(p * freq)
		freq *= 2.0
		amp *= 0.5
	return sum


## Shared height field. Must stay identical to terrain_height() in both shaders.
static func terrain_height(p: Vector2) -> float:
	var h: float = _raw_height(p)
	# Flatten a spawn plateau around the world origin.
	var s: float = smoothstep(5.0, 24.0, p.length())
	h = lerpf(SPAWN_HEIGHT, h, s)
	# Flatten the construction pads so landmarks sit flush with the ground.
	for i in PADS.size():
		var pad: Array = PADS[i]
		var d := (p - (pad[0] as Vector2)).length()
		var r: float = pad[1]
		if d < r:
			var w := 1.0 - smoothstep(r * 0.55, r, d)
			h = lerpf(h, pad[2], w)
	# Carve the dungeon courtyard into its pad.
	var dc := PADS[DUNGEON_INDEX][0] as Vector2
	var pd := (p - dc).length()
	if pd < PIT_OUTER:
		var bowl := 1.0 - smoothstep(PIT_INNER, PIT_OUTER, pd)
		h = lerpf(h, PIT_FLOOR, bowl)
	# Carve a lake basin so the water plane is visible.
	var lake: float = 1.0 - smoothstep(13.0, 34.0, (p - LAKE_CENTER).length())
	return lerpf(h, LAKE_DEPTH, lake)


## The fbm height field without the spawn plateau, pads or lake. Pad target
## heights in PADS were measured with this.
static func _raw_height(p: Vector2) -> float:
	var n: float = fbm(p * TERRAIN_FREQ)
	var t: float = clampf((n - NOISE_MIN) * NOISE_INV_RANGE, 0.0, 1.0)
	return t * 12.0 + pow(t, 3.0) * 10.0 - 3.0


## 0.0 on flat ground, approaching 1.0 on a vertical cliff.
static func slope_at(p: Vector2, epsilon: float = 0.75) -> float:
	var hx: float = terrain_height(p + Vector2(epsilon, 0.0)) - terrain_height(p - Vector2(epsilon, 0.0))
	var hz: float = terrain_height(p + Vector2(0.0, epsilon)) - terrain_height(p - Vector2(0.0, epsilon))
	var n: Vector3 = Vector3(-hx / (2.0 * epsilon), 1.0, -hz / (2.0 * epsilon)).normalized()
	return 1.0 - n.y


## Direction the sun is seen from, matching sun_direction() in sky.gdshader.
static func sun_direction(time_of_day: float, sun_tilt: float) -> Vector3:
	var a: float = (time_of_day - 0.25) * TAU
	var horiz: float = cos(a)
	return Vector3(horiz * cos(sun_tilt), sin(a), horiz * sin(sun_tilt)).normalized()
