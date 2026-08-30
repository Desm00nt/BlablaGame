extends Node

## Headless smoke test. Loads the real main.tscn, lets physics run, then asserts
## that the world was actually built - and that the story layer works.
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
##   * the intro cutscene can be skipped and starts the first quest
##   * the campfire echo advances the quest instantly
##   * the Ingvar dialogue completes the quest and starts the barrow chain
##   * barrow draugr spawn, die and tick the kill counter (and grant XP)
##   * the dungeon garrison spawns far from the safe spawn plateau
##   * shield, gold, XP and supplies all function end to end
##
## What it does NOT cover: shader compilation. --headless uses the dummy
## renderer, so GLSL is parsed but never compiled to SPIR-V.

const CHECK_FRAME: int = 120
const SKIP_CUTSCENE_FRAME: int = 25
const EXPECTED_INSTANCES: int = 5250
const INSTANCE_CEILING: int = 8000
## The spawn plateau is a safe zone: no draugr may camp it.
const SPAWN_SAFE_RADIUS: float = 30.0

var _frame: int = 0
var _failures: int = 0


func _ready() -> void:
	print("[Smoke] main.tscn instantiated, running %d frames" % CHECK_FRAME)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == SKIP_CUTSCENE_FRAME:
		# Deterministic intro: skip the cinematic so the story checks below
		# see a settled state.
		var cutscene := $Main.get_node_or_null(^"Cutscene") as CutscenePlayer
		if cutscene != null:
			cutscene.skip()
		return
	if _frame < CHECK_FRAME:
		return
	set_process(false)
	_check_terrain_collision()
	_check_multimesh_budget()
	_check_player_rests_on_terrain()
	_check_time_and_sun()
	_check_shaders_and_environment()
	_check_gameplay_nodes()
	_check_story()
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

	# Pads: the ground under every landmark must be exactly the pad height,
	# otherwise structures float or sink. The dungeon centre sits in the pit
	# bowl, so its surface is the pit floor instead of the pad level.
	for i in TerrainNoise.PADS.size():
		var pad: Array = TerrainNoise.PADS[i]
		var c := pad[0] as Vector2
		var target := TerrainNoise.PIT_FLOOR if i == TerrainNoise.DUNGEON_INDEX else float(pad[2])
		var got := TerrainNoise.terrain_height(c)
		_expect(absf(got - target) < 0.001,
				"pad at (%0.0f,%0.0f) is flat at %0.2f m" % [c.x, c.y, got])


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


func _check_gameplay_nodes() -> void:
	print("[Smoke] gameplay: trees, sword, enemies, rig, audio")
	var main := $Main
	var trees := main.get_node_or_null(NodePath("WorldGenerator/TreesBody")) as StaticBody3D
	_expect(trees != null, "TreesBody exists under WorldGenerator")
	if trees != null:
		var shapes := 0
		for c in trees.get_children():
			if c is CollisionShape3D:
				shapes += 1
		_expect(shapes >= 40, "tree trunk colliders present (%d)" % shapes)
	var sword := main.get_node_or_null(NodePath("Sword")) as SwordItem
	_expect(sword != null and not sword.picked, "world sword spawned and unpicked")
	var enemy_count := 0
	var first_enemy: Enemy = null
	var closest_enemy_dist := INF
	var player := main.get_node_or_null(^"Player") as Player
	for n in main.get_children():
		if n is Enemy:
			enemy_count += 1
			var e := n as Enemy
			if first_enemy == null:
				first_enemy = e
			if player != null and is_instance_valid(e):
				closest_enemy_dist = minf(closest_enemy_dist,
						e.global_position.distance_to(player.global_position))
	_expect(enemy_count >= 6, "dungeon garrison + barrow guards spawned (%d)" % enemy_count)
	_expect(closest_enemy_dist > SPAWN_SAFE_RADIUS,
			"no enemy camps the spawn plateau (closest %0.1f m)" % closest_enemy_dist)
	if first_enemy != null:
		var hp0 := first_enemy.hp
		first_enemy.take_damage(10.0, first_enemy.global_position + Vector3(1.0, 0.0, 0.0))
		_expect(absf(first_enemy.hp - (hp0 - 10.0)) < 0.001, "enemy takes damage")
		first_enemy.take_damage(9999.0, first_enemy.global_position)
		_expect(first_enemy._state == Enemy.State.DEAD, "enemy dies on lethal damage")
	var audio := main.get_node_or_null(^"AudioManager") as AudioManager
	_expect(audio != null and audio.stream_count() >= 15, "audio manager synthesized its streams")
	if player == null:
		return
	_expect(player.get_node_or_null(^"Rig") is CharacterRig,
			"player has the procedural rig (no capsule mesh)")
	_expect(CharacterRig.EYE_Z < 0.0, "rig faces -Z (eyes on the forward side)")
	if sword != null:
		sword.try_pick_up(player)
		_expect(player.has_sword, "sword pickup registers in the inventory")
		_expect(player.has_item("steel_sword"), "sword lands in the inventory list")
		player.toggle_equip()
		_expect(player.sword_equipped and player.hand_sword.visible,
				"equipping shows the sword in hand")
		player.toggle_equip()
		_expect(not player.sword_equipped, "unequipping hides the sword")
		# First person: the body hides, the camera viewmodel shows instead.
		player.camera_distance = 0.0
		player.toggle_equip()
		player._update_camera()
		var body_rig := player.get_node_or_null(^"Rig") as Node3D
		var fpn := player.get_node_or_null(^"CameraPivot/Camera3D/FPWeapon") as Node3D
		_expect(body_rig != null and not body_rig.visible, "first person hides the body rig")
		_expect(fpn != null, "FP viewmodel exists under the camera")
		_expect(fpn != null and fpn.visible, "equipped sword is visible in first person")
		player.camera_distance = 4.2
		player._update_camera()
		player.toggle_equip()
		# Cutscene camera takeover must keep the hero visible in first person.
		player.camera_distance = 0.0
		player._update_camera()
		player.set_cutscene_mode(true)
		_expect(body_rig != null and body_rig.visible,
				"cutscene mode forces the body rig visible in first person")
		player.set_cutscene_mode(false)
		player._update_camera()
		_expect(body_rig != null and not body_rig.visible,
				"cutscene mode release restores first-person state")
		player.camera_distance = 4.2
		player._update_camera()
		# Shield: give, attach, equip.
		player.give_shield()
		_expect(player.has_shield, "shield grant registers")
		_expect(player.rig.shield_mesh != null, "shield mesh attached to the rig")
		player.toggle_shield_equip()
		_expect(player.shield_equipped, "shield equips to the left hand")
		# Progression: gold, XP, supplies.
		var gold0 := player.gold
		player.add_gold(7)
		_expect(player.gold == gold0 + 7, "gold accumulates")
		var xp0 := player.xp
		player.gain_xp(10)
		_expect(player.xp == xp0 + 10, "xp accumulates")
		player.add_supply("health_potion", 1)
		_expect(player.supply_count("health_potion") == 1, "potions stack")
		player.take_damage(50.0, player.global_position + Vector3(0.0, 0.0, 3.0))
		var hp_after_hit := player.hp
		_expect(hp_after_hit < player.max_hp, "unblocked hit wounds the player")
		_expect(player.use_supply("health_potion"), "potion drinks")
		_expect(player.hp > hp_after_hit, "potion heals")


func _check_story() -> void:
	print("[Smoke] story: quest manager, landmarks, echo, dialogue")
	var main := $Main
	var qm := main.get_node_or_null(^"QuestManager") as QuestManager
	_expect(qm != null, "QuestManager exists")
	var player := main.get_node_or_null(^"Player") as Player
	var cutscene := main.get_node_or_null(^"Cutscene")
	_expect(cutscene != null, "Cutscene node exists")
	if qm == null or player == null:
		return
	_expect(ItemDB.ITEMS.size() >= 6, "item database has the Act I items")
	_expect(qm.is_active("ash"), "intro finished and quest 'Пепел' started")

	var camp := main.get_node_or_null(NodePath("Camp")) as Landmark
	var village := main.get_node_or_null(NodePath("Village")) as Landmark
	var barrow := main.get_node_or_null(NodePath("Barrow")) as Landmark
	var dungeon := main.get_node_or_null(NodePath("Dungeon")) as Landmark
	_expect(camp != null, "camp landmark spawned")
	_expect(village != null and village.npc != null, "village spawned with Ingvar")
	_expect(village != null and village.get_node_or_null(NodePath("VillageChest")) != null,
			"village spawned with a supply chest")
	_expect(barrow != null and barrow.echo_point != null, "barrow spawned with the echo stone")
	_expect(dungeon != null and dungeon.get_node_or_null(NodePath("DungeonChest")) != null,
			"dungeon spawned with the boss chest")

	# The campfire echo, played instantly, advances 'Пепел' to stage 1.
	if camp != null and camp.echo_point != null:
		_expect(camp.echo_point.quest_id == "ash", "campfire echo is wired to the first quest")
		camp.echo_point.interact_instant(player)
		_expect(qm.is_active("ash") and qm.active_stage == 1,
				"campfire echo advanced 'Пепел' to the road stage")

	# Dialogue with Ingvar: completes 'Пепел', starts 'Голос в кургане'.
	var dialogue := main.get_node_or_null(NodePath("DialogueUI")) as DialogueUI
	if dialogue != null:
		_expect(village != null and village.npc.current_dialogue() == "ingvar_1",
				"Ingvar offers the first dialogue while 'Пепел' is active")
		dialogue.open("ingvar_1")
		_expect(dialogue.is_open(), "dialogue opens")
		dialogue.finish_instant()
		_expect(not dialogue.is_open(), "dialogue closes")
	_expect(qm.completed.has("ash"), "'Пепел' completed through the dialogue")
	_expect(qm.is_active("barrow"), "'Голос в кургане' started")

	# Barrow guards: spawned by the quest, counted by dying.
	var barrow_draugrs: Array[Enemy] = []
	for n in main.get_children():
		if n is Enemy and (n as Enemy).kill_tag == "barrow_draugr":
			barrow_draugrs.append(n as Enemy)
	_expect(barrow_draugrs.size() == 3, "3 draugr guard the barrow (%d)" % barrow_draugrs.size())
	if barrow_draugrs.size() > 0:
		var victim := barrow_draugrs[0]
		victim.take_damage(9999.0, victim.global_position)
		_expect(qm.counter_progress() == "(1/3)", "kill counter reads (1/3)")
		_expect(player.xp > 0 or player.level > 1, "the kill granted XP")
	_expect(player.add_item("ashen_shard"), "shard can enter the inventory")
	_expect(player.has_item("ashen_shard"), "shard stays in the inventory")
	_expect(qm.get_marker(StoryData.MARKER_VILLAGE) != Vector3.INF,
			"compass markers registered")
