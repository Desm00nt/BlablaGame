extends SceneTree

## Terrain probe: prints height/slope for candidate landmark sites so the
## builders can be given spots that are flat enough and above water.

const CANDIDATES := {
	"camp_a": Vector2(3.0, -2.5),
	"camp_b": Vector2(2.0, 4.0),
	"camp_c": Vector2(-3.0, 3.0),
	"village_a": Vector2(26.0, 24.0),
	"village_b": Vector2(20.0, 30.0),
	"village_c": Vector2(30.0, 18.0),
	"village_d": Vector2(14.0, 26.0),
	"barrow_a": Vector2(-28.0, 32.0),
	"barrow_b": Vector2(-24.0, 36.0),
	"barrow_c": Vector2(-32.0, 24.0),
	"barrow_d": Vector2(-18.0, 34.0),
	"road_a": Vector2(10.0, 12.0),
	"road_b": Vector2(-10.0, 18.0),
}


func _init() -> void:
	print("spawn (0,0): h=%0.3f slope=%0.3f" % [TerrainNoise.terrain_height(Vector2.ZERO), TerrainNoise.slope_at(Vector2.ZERO)])
	for key in CANDIDATES:
		var p: Vector2 = CANDIDATES[key]
		print("%s (%0.1f, %0.1f): h=%0.3f slope=%0.3f" % [key, p.x, p.y,
				TerrainNoise.terrain_height(p), TerrainNoise.slope_at(p)])
	quit(0)
