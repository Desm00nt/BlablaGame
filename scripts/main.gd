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

## On-screen diagnostics. An exported release build may not open a console
## window at all, and "the character will not move" cannot be debugged from a
## screenshot, so the state that decides it is drawn over the game instead.
var _hud: Label
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
	_build_hud()


## Builds the overlay in code rather than in main.tscn on purpose: it has to work
## even when the node it is diagnosing failed to load.
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DebugHUD"
	layer.layer = 100
	add_child(layer)
	_hud = Label.new()
	_hud.name = "DebugLabel"
	_hud.position = Vector2(12, 12)
	_hud.add_theme_color_override("font_color", Color(1.0, 1.0, 0.4))
	_hud.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hud)


func _process(_delta: float) -> void:
	if _hud != null:
		_hud.text = _status_text()


## Each line rules out one reason the character might not move.
func _status_text() -> String:
	var lines: PackedStringArray = []
	lines.append("fps %.0f | multimesh %d" % [Engine.get_frames_per_second(), _instance_count])

	var player := get_node_or_null(^"Player")
	if player == null:
		lines.append("PLAYER: MISSING - player.tscn did not instantiate")
	else:
		var has_script := "no"
		if player.get_script() != null:
			has_script = "yes"
		lines.append("player: %s, script attached: %s" % [player.get_class(), has_script])
		var body := player as CharacterBody3D
		if body == null:
			lines.append("player is NOT a CharacterBody3D - it cannot move")
		else:
			lines.append("pos %s" % body.position)
			lines.append("vel %s on_floor %s" % [body.velocity, body.is_on_floor()])

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		lines.append("camera: NONE current")
	else:
		lines.append("camera: %s at %s" % [cam.name, cam.global_position])

	lines.append("mouse mode %d (2 = captured)" % Input.mouse_mode)
	var terrain := get_node_or_null(^"TerrainBody")
	var terrain_state := "found"
	if terrain == null:
		terrain_state = "MISSING - nothing to stand on"
	lines.append("terrain body: %s" % terrain_state)
	return "\n".join(lines)


func _check_environment() -> PackedStringArray:
	var bad: PackedStringArray = []
	var env := world_env.environment
	if env == null:
		bad.append("WorldEnvironment has no Environment resource")
		return bad
	if env.sdfgi_enabled:
		bad.append("SDFGI is enabled (banned)")
	# Godot 4 renamed this: ss_reflections_enabled (3.x) -> ssr_enabled.
	# Accessing the old name is a runtime error that would abort _ready()
	# and kill the HUD diagnostics.
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
		# Variant, and `Variant as T` stays Variant - which is a hard
		# parse error in Godot 4.3 and would silently kill this whole
		# script (and the on-screen diagnostics with it).
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
