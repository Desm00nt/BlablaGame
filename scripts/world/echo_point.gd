class_name EchoPoint
extends Node3D

## A place where the hero's "echo" ability works: touching the anchor replays
## fragments of the past. Visual: a slowly orbiting ring of cold rune glyphs.
##
## The vision itself: screen desaturates (Environment.adjustment_saturation),
## letterbox + vignette come up (HUD.set_vision), ghost rigs replay their
## short paths while subtitles run. Then effects are applied through
## QuestManager.run_effects() - usually quest advance + a reward.
##
## Gating: the prompt is only offered while the linked quest sits on
## expected_stage, so echoes can never fire out of order.

var echo_id: String = "campfire"
var quest_id: String = "ash"
var expected_stage: int = 0
var quest_manager: QuestManager = null
var player: Player = null
var hud: GameHUD = null
var environment: Environment = null

var _ring: Node3D
var _glyphs: Array[MeshInstance3D] = []
var _t: float = 0.0
var _playing: bool = false
var _vision_ghosts: Array[CharacterRig] = []
var _vision_defs: Array = []
var _vision_elapsed: float = 0.0


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("echo")
	_build_ring()


func _build_ring() -> void:
	_ring = Node3D.new()
	_ring.name = "EchoRing"
	_ring.position = Vector3(0.0, 1.15, 0.0)
	add_child(_ring)
	var glyph_mesh := BoxMesh.new()
	glyph_mesh.size = Vector3(0.09, 0.14, 0.012)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.72, 0.95, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.45, 0.65, 1.0)
	mat.emission_energy_multiplier = 1.4
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in 5:
		var mi := MeshInstance3D.new()
		mi.mesh = glyph_mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ang := TAU * float(i) / 5.0
		mi.position = Vector3(cos(ang) * 0.42, 0.0, sin(ang) * 0.42)
		# Glyphs stand upright, tangent to the ring.
		mi.rotation.y = -ang
		_ring.add_child(mi)
		_glyphs.append(mi)


func _process(delta: float) -> void:
	_t += delta
	if _ring != null:
		_ring.rotation.y = _t * 0.5
		for i in _glyphs.size():
			var glyph := _glyphs[i]
			glyph.position.y = sin(_t * 1.6 + float(i) * 1.3) * 0.06
	if _playing:
		_vision_elapsed += delta
		_animate_ghosts(delta)


func _available() -> bool:
	if _playing or quest_manager == null:
		return false
	if not quest_manager.is_active(quest_id):
		return false
	return quest_manager.active_stage == expected_stage


## Test hook: run the whole vision with the timeline collapsed.
func interact_instant(by: Node) -> void:
	if not _available():
		return
	var who := by as Player
	if who == null:
		return
	player = who
	_play_vision(true)


func get_prompt() -> String:
	if not _available():
		return ""
	return "Прикоснуться к памяти"


func interact(by: Node) -> void:
	if not _available():
		return
	var who := by as Player
	if who == null:
		return
	player = who
	_play_vision(false)


## Runs the whole vision. instant=true skips the timeline (headless tests).
func _play_vision(instant: bool) -> void:
	_playing = true
	var data: Dictionary = StoryData.ECHOES.get(echo_id, {})
	if data.is_empty():
		_playing = false
		return
	if hud != null:
		hud.set_vision(true)
	if environment != null:
		environment.adjustment_enabled = true
		environment.adjustment_saturation = 0.22
		environment.adjustment_contrast = 1.06
	if player != null:
		player.set_ui_lock(true, false)

	_vision_ghosts = _spawn_ghosts(data.get("ghosts", []))
	_vision_defs = data.get("ghosts", [])
	_vision_elapsed = 0.0

	if instant:
		_finish_vision(data)
		return

	var lines: Array = data.get("lines", [])
	for line in lines:
		var entry: Dictionary = line
		var speaker := str(entry.get("speaker", ""))
		var text := str(entry.get("text", ""))
		var dur := float(entry.get("dur", 3.0))
		if hud != null:
			hud.show_subtitle(speaker, text)
		await get_tree().create_timer(dur).timeout
		if not is_inside_tree():
			return
	_finish_vision(data)


func _spawn_ghosts(defs: Array) -> Array[CharacterRig]:
	var out: Array[CharacterRig] = []
	for def in defs:
		var d: Dictionary = def
		var palette_name := str(d.get("palette", "draugr"))
		var pal: Dictionary = StoryData.GHOST_PALETTES.get(palette_name, {})
		if pal.is_empty():
			continue
		var rig := CharacterRig.new()
		rig.palette_tunic = pal["tunic"]
		rig.palette_armor = pal["armor"]
		rig.palette_skin = pal["skin"]
		rig.palette_leather = pal["leather"]
		rig.palette_cape = pal["cape"]
		rig.palette_eyes = pal["eyes"]
		rig.eyes_emissive = bool(pal.get("emissive", false))
		rig.ghost_alpha = float(pal.get("alpha", 0.6))
		var from: Vector3 = d["from"]
		rig.position = self.position + Vector3(from.x, 0.0, from.z)
		rig.position.y = TerrainNoise.terrain_height(Vector2(rig.position.x, rig.position.z))
		rig.rotation.y = PI  # ghosts face the hero (-Z is forward)
		add_child(rig)
		out.append(rig)
	return out


func _animate_ghosts(delta: float) -> void:
	for i in _vision_ghosts.size():
		if i >= _vision_defs.size():
			break
		var d: Dictionary = _vision_defs[i]
		var rig := _vision_ghosts[i]
		if not is_instance_valid(rig):
			continue
		var delay := float(d.get("delay", 0.0))
		var dur := maxf(float(d.get("dur", 4.0)), 0.1)
		var k := clampf((_vision_elapsed - delay) / dur, 0.0, 1.0)
		var from: Vector3 = d["from"]
		var to: Vector3 = d["to"]
		var local := from.lerp(to, k)
		rig.position = self.position + Vector3(local.x, 0.0, local.z)
		rig.position.y = TerrainNoise.terrain_height(Vector2(rig.position.x, rig.position.z))
		var dir := to - from
		if dir.length() > 0.5:
			var yaw := atan2(-dir.x, -dir.z)
			rig.rotation.y = lerp_angle(rig.rotation.y, yaw, 1.0 - exp(-6.0 * delta))
		var moving := 1.0 if k > 0.0 and k < 1.0 else 0.0
		rig.apply_pose(delta, moving, true, -1.0)


func _finish_vision(data: Dictionary) -> void:
	for rig in _vision_ghosts:
		if is_instance_valid(rig):
			rig.queue_free()
	_vision_ghosts.clear()
	_vision_defs = []
	if environment != null:
		environment.adjustment_saturation = 1.0
		environment.adjustment_contrast = 1.0
		environment.adjustment_enabled = false
	if hud != null:
		hud.set_vision(false)
		hud.hide_subtitle()
	if player != null:
		player.set_ui_lock(false, false)
	if quest_manager != null:
		quest_manager.run_effects(data.get("effects", []), player)
	_playing = false
