extends Node

## Headless smoke test. Loads the real main.tscn, lets physics run, then asserts
## that the world was actually built.
##
## Run:  godot --headless --quit-after 240 res://tests/smoke.tscn
##
## What this covers that the Python checks cannot:
##   * every GDScript file parses and its _ready()/_process() bodies execute
##   * world_generator.gd really produces meshes, materials and MultiMeshes
##   * the terrain collision surface matches terrain_height() at real vertices
##   * the player falls and is stopped by that collision (not by a box at y=0)
##   * _basis_for_sun() produces an orthonormal basis matching sun_direction()
##   * each shader parsed far enough to expose its uniforms
##
## What it does NOT cover: shader compilation. --headless uses the dummy
## renderer, so GLSL is parsed but never compiled to SPIR-V.

const CHECK_FRAME: int = 120
const EXPECTED_INSTANCES: int = 2081
const INSTANCE_CEILING: int = 3000

var _frame: int = 0
var _failures: int = 0


func _ready() -> void:
	print("[Smoke] main.tscn instantiated, running %d frames" % CHECK_FRAME)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame < CHECK_FRAME:
		return
	set_process(false)
	_check_terrain_collision()
	_check_multimesh_budget()
	_check_player_rests_on_terrain()
	_check_time_and_sun()
	_check_shaders_and_environment()
	print("")
	if _failures == 0:
		print("[Smoke] PASS")
		get_tree().quit(0)
	else:
		print("[Smoke] FAIL (%d assertion(s))" % _failures)
		get_tree().quit(1)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   " + msg)
	else:
		_failures += 1
		print("  FAIL " + msg)


# --- checks ------------------------------------------------------------------

func _check_terrain_collision() -> void:
	print("[Smoke] terrain collision")
	var main := $Main
	var body := main.get_node_or_null(^"TerrainBody")
	_expect(body is StaticBody3D, "TerrainBody StaticBody3D was created")
	if body == null:
		return
	var col := body.get_node_or_null(^"TerrainCollisionShape") as CollisionShape3D
	_expect(col != null and col.shape is ConcavePolygonShape3D,
			"TerrainCollisionShape is a ConcavePolygonShape3D")
	if col == null or col.shape == null:
		return
	var faces: PackedVector3Array = (col.shape as ConcavePolygonShape3D).get_faces()
	_expect(faces.size() >= 3000, "collision mesh has %d vertices" % faces.size())
	print("       %d triangles" % (faces.size() / 3))

	# The whole point: collision must sit on the displaced surface, not at y=0.
	var worst: float = 0.0
	var sampled: int = 0
	for i in range(0, faces.size(), 11):
		var v: Vector3 = faces[i]
		worst = maxf(worst, absf(v.y - TerrainNoise.terrain_height(Vector2(v.x, v.z))))
		sampled += 1
	_expect(worst < 0.001,
			"collision follows terrain_height() over %d samples (worst %0.6f m)" % [sampled, worst])


func _check_multimesh_budget() -> void:
	print("[Smoke] MultiMesh budget")
	var total: int = 0
	var nodes: int = 0
	var empty: int = 0
	var no_range: int = 0
	var stack: Array[Node] = [$Main]
	while not stack.is_empty():
		# pop_back() returns Variant; inferring with `:=` from a Variant
		# (even through `as`) is a hard parse error in Godot 4.3.
		var n: Node = stack.pop_back()
		if n is MultiMeshInstance3D:
			var mmi := n as MultiMeshInstance3D
			nodes += 1
			var mm := mmi.multimesh
			if mm == null or mm.instance_count == 0:
				empty += 1
			else:
				total += mm.instance_count
			if mmi.visibility_range_end <= 0.0:
				no_range += 1
		for c in n.get_children():
			stack.append(c)
	print("       %d MultiMeshInstance3D nodes, %d instances" % [nodes, total])
	_expect(nodes > 1, "props were chunked instead of one world-spanning MultiMesh")
	_expect(empty == 0, "%d MultiMesh nodes have no instances" % empty)
	_expect(no_range == 0, "%d MultiMesh nodes lack visibility_range_end" % no_range)
	_expect(total == EXPECTED_INSTANCES,
			"instance count is %d (expected %d)" % [total, EXPECTED_INSTANCES])
	_expect(total <= INSTANCE_CEILING, "instance ceiling %d respected" % INSTANCE_CEILING)


func _check_player_rests_on_terrain() -> void:
	print("[Smoke] player vs terrain")
	var player := $Main.get_node_or_null(^"Player") as CharacterBody3D
	_expect(player != null, "Player exists")
	if player == null:
		return
	var px := player.global_position.x
	var pz := player.global_position.z
	var ground := TerrainNoise.terrain_height(Vector2(px, pz))
	print("       player y=%0.3f at (%0.1f, %0.1f), terrain y=%0.3f, on_floor=%s"
			% [player.global_position.y, px, pz, ground, player.is_on_floor()])
	_expect(player.global_position.y > ground - 0.35,
			"player did not fall through the collision mesh")
	_expect(player.global_position.y < ground + 1.5,
			"player is not floating above the terrain (a box collider would do this)")


func _check_time_and_sun() -> void:
	print("[Smoke] day/night cycle")
	var main := $Main
	var tm := main.get_node_or_null(^"TimeManager")
	var sun := main.get_node_or_null(^"DirectionalLight3D") as DirectionalLight3D
	_expect(tm != null, "TimeManager exists")
	_expect(sun != null, "DirectionalLight3D exists")
	if tm == null or sun == null:
		return
	_expect(tm.time_of_day != tm.start_time_of_day,
			"time_of_day advanced to %0.6f" % tm.time_of_day)
	var b := sun.global_transform.basis
	var finite: bool = (is_finite(b.x.x) and is_finite(b.x.y) and is_finite(b.x.z)
			and is_finite(b.y.x) and is_finite(b.y.y) and is_finite(b.y.z)
			and is_finite(b.z.x) and is_finite(b.z.y) and is_finite(b.z.z))
	_expect(finite, "sun basis contains no NaN")
	var unit: bool = (absf(b.x.length() - 1.0) < 0.001
			and absf(b.y.length() - 1.0) < 0.001
			and absf(b.z.length() - 1.0) < 0.001)
	_expect(unit, "sun basis axes are unit length")
	var orthogonal: bool = (absf(b.x.dot(b.y)) < 0.001
			and absf(b.y.dot(b.z)) < 0.001
			and absf(b.x.dot(b.z)) < 0.001)
	_expect(orthogonal, "sun basis axes are orthogonal")
	_expect(absf(b.determinant() - 1.0) < 0.001,
			"sun basis determinant is +1 (got %0.4f)" % b.determinant())
	var want: Vector3 = tm.sun_direction()
	# The sun transform is refreshed at update_rate Hz (6 by default), while
	# time_of_day keeps advancing, so the basis may lag up to 1/update_rate
	# seconds behind. The sun moves TAU / day_length_seconds rad/s
	# (~0.0035 rad per 1/6 s), so 0.005 absorbs the full lag plus float32
	# noise without hiding a real error.
	_expect(b.z.distance_to(want) < 0.005,
			"light -Z points away from sun_direction() (delta %0.5f)" % b.z.distance_to(want))


func _check_shaders_and_environment() -> void:
	print("[Smoke] shaders and environment")
	var main := $Main
	var we := main.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	_expect(we != null, "WorldEnvironment exists")
	if we == null:
		return
	var env := we.environment
	_expect(not env.sdfgi_enabled, "SDFGI off")
	# Godot 4 renamed ss_reflections_enabled (3.x) to ssr_enabled.
	_expect(not env.ssr_enabled, "SSR off")
	_expect(not env.volumetric_fog_enabled, "Volumetric fog off")
	_expect(env.ssao_enabled, "SSAO on")
	_expect(env.glow_enabled, "Glow on")
	_expect(env.tonemap_mode == Environment.TONE_MAPPER_ACES, "ACES tonemap")
	var sun := main.get_node_or_null(^"DirectionalLight3D") as DirectionalLight3D
	_expect(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
			"directional shadows use 2 splits")

	# A uniform is only visible if the shader source parsed successfully.
	var sky_mat: ShaderMaterial = null
	if env.sky != null:
		sky_mat = env.sky.sky_material as ShaderMaterial
	_expect(sky_mat != null and sky_mat.get_shader_parameter("time_of_day") != null,
			"sky.gdshader parsed and exposes time_of_day")
	for pair in [["Terrain", "grass_line"], ["Water", "wave_height"]]:
		var mi := main.get_node_or_null(NodePath(pair[0])) as MeshInstance3D
		var prim: PrimitiveMesh = null
		if mi != null:
			prim = mi.mesh as PrimitiveMesh
		var mat: ShaderMaterial = null
		if prim != null:
			mat = prim.material as ShaderMaterial
		var ok: bool = mat != null and mat.get_shader_parameter(pair[1]) != null
		_expect(ok, "%s shader material parsed and exposes %s" % [pair[0], pair[1]])
