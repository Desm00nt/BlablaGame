class_name PickupItem
extends Node3D

## A small world item that goes straight into the inventory on interact:
## readable notes, quest trinkets. Visual is a primitive per item type -
## a note is a paper sheet with scribbles, a quest item a soft-glowing piece.

var item_id: String = "caravan_note"
var toast: String = ""

var _t: float = 0.0
var _visual: Node3D


func _ready() -> void:
	add_to_group("interactable")
	_visual = Node3D.new()
	_visual.position = Vector3(0.0, 0.06, 0.0)
	add_child(_visual)
	var meta := ItemDB.get_item(item_id)
	var kind := str(meta.get("type", "note"))
	if kind == "note":
		_build_note()
	else:
		_build_relic()


func _build_note() -> void:
	var paper := BoxMesh.new()
	paper.size = Vector3(0.30, 0.012, 0.22)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.84, 0.79, 0.66)
	mat.roughness = 0.95
	var mi := MeshInstance3D.new()
	mi.mesh = paper
	mi.material_override = mat
	_visual.add_child(mi)
	var ink := BoxMesh.new()
	ink.size = Vector3(0.22, 0.013, 0.02)
	var ink_mat := StandardMaterial3D.new()
	ink_mat.albedo_color = Color(0.25, 0.22, 0.18)
	var ink_mi := MeshInstance3D.new()
	ink_mi.mesh = ink
	ink_mi.material_override = ink_mat
	ink_mi.position = Vector3(0.0, 0.002, -0.04)
	_visual.add_child(ink_mi)


func _build_relic() -> void:
	var gem := PrismMesh.new()
	gem.size = Vector3(0.16, 0.22, 0.12)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = UIStyle.GOLD
	mat.emission_enabled = true
	mat.emission = UIStyle.GOLD
	mat.emission_energy_multiplier = 0.7
	var mi := MeshInstance3D.new()
	mi.mesh = gem
	mi.material_override = mat
	mi.position = Vector3(0.0, 0.14, 0.0)
	_visual.add_child(mi)


func _physics_process(delta: float) -> void:
	# Gentle bob so the item reads as interactive without any glow spam.
	_t += delta
	_visual.position.y = 0.06 + sin(_t * 2.0) * 0.012


func get_prompt() -> String:
	return "Взять: " + ItemDB.display_name(item_id)


func interact(by: Node) -> void:
	if by.has_method("add_item"):
		by.add_item(item_id)
	queue_free()
