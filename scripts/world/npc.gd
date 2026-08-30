class_name StoryNPC
extends Node3D

## A standing NPC with a dialogue. Faces the player when nearby (cheap
## lerp_angle on the rig yaw), breathes via apply_pose, and opens the
## dialogue UI through the generic interactable contract.
##
## dialogue_picker (optional Callable) decides WHICH dialogue fits the quest
## state right now; if it returns "" the NPC has nothing to say yet and no
## prompt is shown. Falls back to dialogue_id.

var npc_name: String = "Странник"
var dialogue_id: String = ""
var dialogue_picker: Callable = Callable()
var dialogue_ui: DialogueUI = null

var _rig: CharacterRig
var _player_ref: Node3D = null


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("npc")


func setup_rig(palette: Dictionary) -> void:
	_rig = CharacterRig.new()
	_rig.palette_tunic = palette.get("tunic", Color(0.30, 0.28, 0.38))
	_rig.palette_armor = palette.get("armor", Color(0.55, 0.50, 0.40))
	_rig.palette_skin = palette.get("skin", Color(0.80, 0.64, 0.50))
	_rig.palette_leather = palette.get("leather", Color(0.30, 0.22, 0.15))
	_rig.palette_cape = palette.get("cape", Color(0.24, 0.22, 0.30))
	_rig.palette_eyes = palette.get("eyes", Color(0.10, 0.10, 0.12))
	add_child(_rig)


func current_dialogue() -> String:
	if dialogue_picker.is_valid():
		var picked := str(dialogue_picker.call())
		return picked
	return dialogue_id


func _physics_process(delta: float) -> void:
	if _rig == null:
		return
	# Turn toward an approaching player - storytellers look at their audience.
	if _player_ref != null and is_instance_valid(_player_ref):
		var to_player := _player_ref.global_position - global_position
		to_player.y = 0.0
		if to_player.length() < 4.5:
			var yaw := atan2(-to_player.x, -to_player.z)
			rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-4.0 * delta))
	_rig.apply_pose(delta, 0.0, true, -1.0)


func get_prompt() -> String:
	if current_dialogue() == "":
		return ""
	return "Говорить: " + npc_name


func interact(by: Node) -> void:
	var id := current_dialogue()
	if id == "" or dialogue_ui == null:
		return
	if by is Node3D:
		_player_ref = by as Node3D
	dialogue_ui.open(id)
