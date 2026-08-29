extends Node3D

## Scene root. Owns the performance-budget guard, spawns the interactive
## world (sword pickup, roaming draugr, the three story landmarks) and wires
## the story layer together: QuestManager + HUD + DialogueUI + intro
## cutscene + echo points.
##
## The 2 GB VRAM ceiling is a hard project constraint, so instead of trusting
## that nobody will tick a box in the editor, the constraint is checked at
## startup and reported.

const MAX_MULTIMESH_INSTANCES: int = 3000
const MAX_MSAA_3D: int = 1  # 0 = disabled, 1 = 2x. 2 (4x) and above are banned.

## Roaming draugr camps (XZ). Heights come from TerrainNoise at spawn time.
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

## Story landmarks (XZ). Probed with tests/probe_terrain.gd: all three sit on
## flat ground above the water line.
const CAMP_POS: Vector2 = Vector2(3.0, -2.5)
const VILLAGE_POS: Vector2 = Vector2(26.0, 24.0)
const BARROW_POS: Vector2 = Vector2(-28.0, 32.0)

## Barrow guards, offset from the door.
const BARROW_DRAUGR_OFFSETS: Array[Vector2] = [
	Vector2(-2.5, 9.5),
	Vector2(1.5, 10.5),
	Vector2(5.0, 9.0),
]

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $DirectionalLight3D

var _hud: GameHUD
var _qm: QuestManager
var _dialogue_ui: DialogueUI
var _cutscene: CutscenePlayer
var _camp: Landmark
var _village: Landmark
var _barrow: Landmark
var _instance_count: int = 0
var _barrow_draugrs_spawned: bool = false


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

	var player := get_node(^"Player") as Player

	_spawn_world_items()
	_spawn_landmarks()

	# Story layer.
	_qm = QuestManager.new()
	_qm.name = "QuestManager"
	add_child(_qm)
	_qm.set_marker(StoryData.MARKER_CAMPFIRE, _camp.global_position + _camp.fire_pos)
	_qm.set_marker(StoryData.MARKER_VILLAGE, _village.global_position)
	_qm.set_marker(StoryData.MARKER_BARROW, _barrow.global_position + Vector3(0.0, 0.0, 6.1))
	_qm.set_marker(StoryData.MARKER_BARROW_STONE, _barrow.global_position + _barrow.stone_pos)
	_qm.quest_started.connect(_on_quest_started)

	_hud = GameHUD.new()
	_hud.name = "HUD"
	add_child(_hud)
	_hud.setup(player, _instance_count)
	_hud.connect_quests(_qm)

	_dialogue_ui = DialogueUI.new()
	_dialogue_ui.name = "DialogueUI"
	_dialogue_ui.player = player
	_dialogue_ui.quest_manager = _qm
	add_child(_dialogue_ui)

	for lm: Landmark in [_camp, _village, _barrow]:
		if lm.echo_point != null:
			lm.echo_point.quest_manager = _qm
			lm.echo_point.player = player
			lm.echo_point.hud = _hud
			lm.echo_point.environment = world_env.environment
	if _village.npc != null:
		_village.npc.dialogue_ui = _dialogue_ui
		_village.npc.dialogue_picker = _pick_ingvar_dialogue

	# Intro: hero lies among the ashes until the cutscene releases him.
	player.begin_intro()
	_cutscene = CutscenePlayer.new()
	_cutscene.name = "Cutscene"
	_cutscene.player = player
	_cutscene.hud = _hud
	add_child(_cutscene)
	_cutscene.finished.connect(_on_intro_finished)
	_cutscene.start()

	print("[Story] Аш-Вейл ждёт. Каменный Брод - на юго-восток.")


func _pick_ingvar_dialogue() -> String:
	if _qm.is_active("ash"):
		return "ingvar_1"
	if _qm.is_active("barrow") and _qm.active_stage >= 2:
		return "ingvar_2"
	return ""


func _on_intro_finished() -> void:
	_qm.start_quest("ash")
	_hud.set_symbol(true, true)


func _on_quest_started(id: String, _title: String = "") -> void:
	if id == "barrow":
		_spawn_barrow_draugrs()


func _spawn_barrow_draugrs() -> void:
	if _barrow_draugrs_spawned:
		return
	_barrow_draugrs_spawned = true
	var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
	var base := _barrow.global_position
	var count := 0
	for off: Vector2 in BARROW_DRAUGR_OFFSETS:
		var p := Vector2(base.x + off.x, base.z + off.y)
		var e := enemy_scene.instantiate() as Enemy
		e.position = Vector3(p.x, TerrainNoise.terrain_height(p) + 0.1, p.y)
		e.name = "BarrowDraugr_%d" % count
		e.kill_tag = "barrow_draugr"
		e.died.connect(_on_enemy_died)
		add_child(e)
		count += 1
	print("[Story] %d draugr guard the barrow" % count)


func _on_enemy_died(tag: String) -> void:
	if _qm != null and tag != "":
		_qm.notify_kill(tag)


## Spawns the sword pickup and the roaming enemies on the actual displaced
## surface.
func _spawn_world_items() -> void:
	var sword_scene: PackedScene = preload("res://scenes/sword.tscn")
	var sword := sword_scene.instantiate() as SwordItem
	sword.position = Vector3(SWORD_SPAWN.x, TerrainNoise.terrain_height(SWORD_SPAWN) + 0.55,
			SWORD_SPAWN.y)
	sword.name = "Sword"
	add_child(sword)

	var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
	for p: Vector2 in ENEMY_SPAWNS:
		var e := enemy_scene.instantiate() as Enemy
		e.position = Vector3(p.x, TerrainNoise.terrain_height(p) + 0.1, p.y)
		e.name = "Enemy_%d_%d" % [int(p.x), int(p.y)]
		e.died.connect(_on_enemy_died)
		add_child(e)
	print("[Main] spawned 1 sword + %d enemies" % ENEMY_SPAWNS.size())


func _spawn_landmarks() -> void:
	_camp = _make_landmark("Camp", "camp", CAMP_POS)
	_village = _make_landmark("Village", "village", VILLAGE_POS)
	_barrow = _make_landmark("Barrow", "barrow", BARROW_POS)
	print("[Main] landmarks: camp %s village %s barrow %s" % [CAMP_POS, VILLAGE_POS, BARROW_POS])


func _make_landmark(node_name: String, kind: String, at: Vector2) -> Landmark:
	var lm := Landmark.new()
	lm.name = node_name
	lm.kind = kind
	lm.position = Vector3(at.x, TerrainNoise.terrain_height(at), at.y)
	add_child(lm)
	return lm


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
