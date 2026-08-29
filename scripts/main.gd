extends Node3D

## Scene root. Owns the performance-budget guard and spawns the interactive
## world items (the sword pickup and the enemies) at their exact terrain
## heights, which only TerrainNoise knows at runtime.
##
## The 2 GB VRAM ceiling is a hard project constraint, so instead of trusting
## that nobody will tick a box in the editor, the constraint is checked at
## startup and reported.

const MAX_MULTIMESH_INSTANCES: int = 3000
const MAX_MSAA_3D: int = 1  # 0 = disabled, 1 = 2x. 2 (4x) and above are banned.

## Enemy camp positions (XZ). Heights come from TerrainNoise at spawn time.
## All points start far enough from the origin that the spawn plateau is a
## safe zone, but close enough that a walk reaches them.
const ENEMY_SPAWNS: Array[Vector2] = [
	Vector2(10.0, 11.0),
	Vector2(-13.0, 8.0),
	Vector2(17.0, -10.0),
	Vector2(-10.0, -17.0),
	Vector2(25.0, 19.0),
	Vector2(-23.0, -9.0),
]

const SWORD_SPAWN: Vector2 = Vector2(2.6, 4.5)

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $DirectionalLight3D

var _hud: GameHUD
var _instance_count: int = 0


func _ready() -> void:
	var violations: PackedStringArray = []
	violations.append_array(_check_environment())
	violations.append_array(_check_project_settings())
	var instances := _count_multimesh_instances()
	_instance_count = instances
	if instances > MAX_MULTIMESH_INSTANCES:
		violations.append("MultiMesh instances %d > %d" % [instances, MAX_MULTIMESH_INSTANCES])

	for v in violations:
		push_error("[BudgetGuard] " + v)

	print("[Main] MultiMesh instances %d/%d | MSAA3D x%d | shadows %s | SSAO %s | glow %s"
			% [instances, MAX_MULTIMESH_INSTANCES,
				int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0)),
				_shadow_mode_name(),
				world_env.environment.ssao_enabled,
				world_env.environment.glow_enabled])
	if violations.is_empty():
		print("[Main] performance budget OK")

	_spawn_world_items()

	_hud = GameHUD.new()
	_hud.name = "HUD"
	add_child(_hud)
	_hud.setup(get_node(^"Player") as Player, _instance_count)


## Spawns the sword pickup and the enemies on the actual displaced surface.
func _spawn_world_items() -> void:
	var sword_scene: PackedScene = preload("res://scenes/sword.tscn")
	var sword := sword_scene.instantiate() as SwordItem
	sword.position = Vector3(SWORD_SPAWN.x, TerrainNoise.terrain_height(SWORD_SPAWN) + 0.55,
			SWORD_SPAWN.y)
	add_child(sword)

	var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
	for p: Vector2 in ENEMY_SPAWNS:
		var e := enemy_scene.instantiate() as Enemy
		e.position = Vector3(p.x, TerrainNoise.terrain_height(p) + 0.1, p.y)
		e.name = "Enemy_%d_%d" % [int(p.x), int(p.y)]
		add_child(e)
	print("[Main] spawned 1 sword + %d enemies" % ENEMY_SPAWNS.size())


func _check_environment() -> PackedStringArray:
	var bad: PackedStringArray = []
	var env := world_env.environment
	if env == null:
		bad.append("WorldEnvironment has no Environment resource")
		return bad
	if env.sdfgi_enabled:
		bad.append("SDFGI is enabled (banned)")
		# Godot 4 renamed this: ss_reflections_enabled (3.x) -> ssr_enabled.
		# Accessing the old name is a runtime error that would abort _ready().
	if env.ssr_enabled:
		bad.append("SSR is enabled (banned)")
	if env.volumetric_fog_enabled:
		bad.append("Volumetric Fog is enabled (banned - use fog_enabled distance fog)")
	return bad


func _check_project_settings() -> PackedStringArray:
	var bad: PackedStringArray = []
	var msaa := int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0))
	if msaa > MAX_MSAA_3D:
		bad.append("msaa_3d=%d exceeds 2x (banned)" % msaa)
	var method := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))
	if method != "forward_plus":
		bad.append("renderer/rendering_method is '%s', expected 'forward_plus'" % method)
	return bad


func _count_multimesh_instances() -> int:
	var total := 0
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		# Array.pop_back() returns Variant; `var n := ...` would infer
		# Variant, and `Variant as T` stays Variant - a hard parse error in
		# Godot 4.3. Type the variable explicitly.
		var n: Node = stack.pop_back()
		if n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm != null:
				total += mm.instance_count
		for c in n.get_children():
			stack.append(c)
	return total


func _shadow_mode_name() -> String:
	match sun.directional_shadow_mode:
		DirectionalLight3D.SHADOW_ORTHOGONAL:
			return "orthogonal"
		DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS:
			return "2 splits (max %.0f m)" % sun.directional_shadow_max_distance
		DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS:
			return "4 splits"
	return "unknown"
