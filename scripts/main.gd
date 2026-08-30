extends Node3D

## Scene root. Owns the performance-budget guard, spawns the interactive
## world (sword pickup, roaming draugr, the three story landmarks) and wires
## the story layer together: QuestManager + HUD + DialogueUI + intro
## cutscene + echo points.
##
## The 2 GB VRAM ceiling is a hard project constraint, so instead of trusting
## that nobody will tick a box in the editor, the constraint is checked at
## startup and reported.

const MAX_MULTIMESH_INSTANCES: int = 8000
const MAX_MSAA_3D: int = 1  # 0 = disabled, 1 = 2x. 2 (4x) and above are banned.

## Roaming draugr camps are GONE: the spawn plateau is a safe zone (the
## player asked for it - starting fights interrupted the intro). All the
## combat lives in the dungeon courtyard and at the barrow now.

const SWORD_SPAWN: Vector2 = Vector2(2.6, 4.5)

## Story landmarks (XZ). Heights/flattening come from TerrainNoise.PADS -
## every landmark sits on its own construction pad, so structures are flush
## with the ground. Distances from spawn: village 68 m, dungeon 82 m,
## barrow 106 m (4x-area world).
const CAMP_POS: Vector2 = Vector2(3.0, -2.5)
const VILLAGE_POS: Vector2 = Vector2(36.0, 58.0)
const BARROW_POS: Vector2 = Vector2(-72.0, 78.0)
const DUNGEON_POS: Vector2 = Vector2(-40.0, -72.0)

## Barrow guards, offset from the door.
const BARROW_DRAUGR_OFFSETS: Array[Vector2] = [
	Vector2(-2.5, 9.5),
	Vector2(1.5, 10.5),
	Vector2(5.0, 9.0),
]

## Dungeon garrison, offset from the courtyard centre (local XZ of the
## landmark node; the node is rotated so local +Z faces the approach).
const DUNGEON_DRAUGR_OFFSETS: Array[Vector2] = [
	Vector2(-4.6, -3.2),
	Vector2(4.4, -3.6),
	Vector2(-4.0, 3.4),
	Vector2(0.0, -5.4),
	Vector2(5.0, 2.6),
]
const DUNGEON_BOSS_OFFSET: Vector2 = Vector2(2.3, 1.8)

## Loot tables for the death handler (gold amount, potion/whetstone chances).
const LOOT_GOLD_DRAUGR: Vector2i = Vector2i(5, 14)
const LOOT_GOLD_BOSS: Vector2i = Vector2i(40, 70)
const LOOT_POTION_CHANCE: float = 0.30
const LOOT_WHETSTONE_CHANCE: float = 0.08
const XP_DRAUGR: int = 25
const XP_BOSS: int = 120

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $DirectionalLight3D

var _hud: GameHUD
var _qm: QuestManager
var _dialogue_ui: DialogueUI
var _cutscene: CutscenePlayer
var _camp: Landmark
var _village: Landmark
var _barrow: Landmark
var _dungeon: Landmark
var _audio: AudioManager
var _instance_count: int = 0
var _barrow_draugrs_spawned: bool = false
var _player_ref: Player


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
	_player_ref = player

	# Audio before the world spawns so landmark fire loops can register.
	_audio = AudioManager.new()
	_audio.name = "AudioManager"
	add_child(_audio)

	_spawn_world_items()
	_spawn_landmarks()
	_audio.add_fire(_camp.global_position + _camp.fire_pos)
	_audio.add_fire(_village.global_position + _village.fire_pos)
	# The courtyard brazier cluster reads as one fire from a distance.
	_audio.add_fire(_dungeon.global_position + Vector3(0.0, 1.0, 0.0), true)

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

	print("[Story] Аш-Вейл ждёт. Каменный Брод - к северо-востоку, Курганные Чертоги - к юго-западу.")


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
		e.died.connect(_on_enemy_died.bind(e))
		add_child(e)
		count += 1
	print("[Story] %d draugr guard the barrow" % count)


func _on_enemy_died(tag: String, enemy: Enemy = null) -> void:
	if _qm != null and tag != "":
		_qm.notify_kill(tag)
	if enemy == null or _player_ref == null or not is_instance_valid(enemy):
		return
	# XP + loot. Regular draugr carry pocket change, the warden much more.
	var boss := enemy.is_boss
	_player_ref.gain_xp(XP_BOSS if boss else XP_DRAUGR)
	var at := enemy.global_position
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var gold_range := LOOT_GOLD_BOSS if boss else LOOT_GOLD_DRAUGR
	_spawn_drop_gold(rng.randi_range(gold_range.x, gold_range.y), at)
	if boss:
		_spawn_drop_supply("health_potion", 1, at, Vector3(1.2, 0.0, 0.4))
		_spawn_drop_supply("whetstone", 1, at, Vector3(-1.1, 0.0, -0.5))
	else:
		if rng.randf() < LOOT_POTION_CHANCE:
			_spawn_drop_supply("health_potion", 1, at,
					Vector3(rng.randf_range(-0.8, 0.8), 0.0, rng.randf_range(-0.8, 0.8)))
		if rng.randf() < LOOT_WHETSTONE_CHANCE:
			_spawn_drop_supply("whetstone", 1, at,
					Vector3(rng.randf_range(-0.8, 0.8), 0.0, rng.randf_range(-0.8, 0.8)))


func _spawn_drop_gold(amount: int, at: Vector3) -> void:
	var drop := LootDrop.new()
	drop.drop_kind = "gold"
	drop.amount = amount
	drop.position = at + Vector3(0.0, 0.4, 0.0)
	drop.toss_velocity = Vector3(randf_range(-0.8, 0.8), 2.2, randf_range(-0.8, 0.8))
	add_child(drop)


func _spawn_drop_supply(id: String, count: int, at: Vector3, spread: Vector3) -> void:
	var drop := LootDrop.new()
	drop.drop_kind = "supply"
	drop.supply_id = id
	drop.amount = count
	drop.position = at + spread * 0.5 + Vector3(0.0, 0.4, 0.0)
	drop.toss_velocity = spread * 1.4 + Vector3(0.0, 2.0, 0.0)
	add_child(drop)


## Spawns the sword pickup. Combat lives in the dungeon/barrow now, so the
## starting plateau keeps only the tutorial weapon and no enemies.
func _spawn_world_items() -> void:
	var sword_scene: PackedScene = preload("res://scenes/sword.tscn")
	var sword := sword_scene.instantiate() as SwordItem
	sword.position = Vector3(SWORD_SPAWN.x, TerrainNoise.terrain_height(SWORD_SPAWN) + 0.55,
			SWORD_SPAWN.y)
	sword.name = "Sword"
	add_child(sword)
	print("[Main] spawned the world sword (spawn plateau is a safe zone)")


func _spawn_landmarks() -> void:
	_camp = _make_landmark("Camp", "camp", CAMP_POS)
	_village = _make_landmark("Village", "village", VILLAGE_POS)
	_barrow = _make_landmark("Barrow", "barrow", BARROW_POS)
	_dungeon = _make_landmark("Dungeon", "dungeon", DUNGEON_POS)
	# Rotate the courtyard so its gate faces the approach from the spawn.
	var to_spawn := Vector3(-DUNGEON_POS.x, 0.0, -DUNGEON_POS.y)
	_dungeon.rotation.y = atan2(to_spawn.x, to_spawn.z)
	_spawn_dungeon_garrison()
	print("[Main] landmarks: camp %s village %s barrow %s dungeon %s"
			% [CAMP_POS, VILLAGE_POS, BARROW_POS, DUNGEON_POS])


## The dungeon garrison: five draugr on the floor plus a boss by the chest.
## Spawns immediately (no quest gate): the pit is the world's combat sandbox.
func _spawn_dungeon_garrison() -> void:
	var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
	var count := 0
	for off: Vector2 in DUNGEON_DRAUGR_OFFSETS:
		var wp := _dungeon.to_global(Vector3(off.x, 0.0, off.y))
		var e := enemy_scene.instantiate() as Enemy
		e.position = Vector3(wp.x, TerrainNoise.terrain_height(Vector2(wp.x, wp.z)) + 0.1, wp.z)
		e.name = "DungeonDraugr_%d" % count
		e.respawn_delay = 40.0
		e.died.connect(_on_enemy_died.bind(e))
		add_child(e)
		count += 1
	var bp := _dungeon.to_global(Vector3(DUNGEON_BOSS_OFFSET.x, 0.0, DUNGEON_BOSS_OFFSET.y))
	var boss := enemy_scene.instantiate() as Enemy
	boss.position = Vector3(bp.x, TerrainNoise.terrain_height(Vector2(bp.x, bp.z)) + 0.1, bp.z)
	boss.name = "DungeonBoss"
	boss.is_boss = true
	boss.max_hp = 260.0
	boss.damage = 26.0
	boss.chase_speed = 3.0
	boss.respawn_delay = 120.0
	boss.scale = Vector3(1.28, 1.28, 1.28)
	boss.died.connect(_on_enemy_died.bind(boss))
	add_child(boss)
	print("[Story] %d draugr + 1 warden hold the courtyard" % count)


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
