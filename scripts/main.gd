extends Node3D

## Scene root. Owns nothing but the performance-budget guard.
##
## The 2 GB VRAM ceiling is a hard project constraint, so instead of trusting
## that nobody will tick a box in the editor, the constraint is checked at
## startup and reported. Anything banned shows up in the output log on the very
## first frame - including in the CI export, where stdout is captured.

const MAX_MULTIMESH_INSTANCES: int = 3000
const MAX_MSAA_3D: int = 1  # 0 = disabled, 1 = 2x. 2 (4x) and above are banned.

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $DirectionalLight3D


func _ready() -> void:
	var violations: PackedStringArray = []
	violations.append_array(_check_environment())
	violations.append_array(_check_project_settings())
	var instances := _count_multimesh_instances()
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


func _check_environment() -> PackedStringArray:
	var bad: PackedStringArray = []
	var env := world_env.environment
	if env == null:
		bad.append("WorldEnvironment has no Environment resource")
		return bad
	if env.sdfgi_enabled:
		bad.append("SDFGI is enabled (banned)")
	if env.ss_reflections_enabled:
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
		var n := stack.pop_back()
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
